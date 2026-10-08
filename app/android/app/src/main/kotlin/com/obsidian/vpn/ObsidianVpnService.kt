package com.obsidian.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.IpPrefix
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.obsidian.core.mobile.Mobile
import com.obsidian.core.mobile.SocketProtector
import com.obsidian.core.mobile.StatsListener
import com.obsidian.core.mobile.StatusListener
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetAddress
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadFactory
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Input of one tunnel start. Kept in [VpnBridge.lastRequest] so applySplit can restart the tunnel. */
data class TunnelRequest(
    val profileId: String,
    val name: String,
    val serverHost: String,
    val configJson: String,
)

/**
 * Owns the Android VPN interface and the Go tunnel session.
 *
 * Threading: lifecycle work (establish, Go start and stop) runs on [executor], one task at a time.
 * Go callbacks arrive on Go threads. They check [activeGeneration] (volatile) and hand teardown
 * work back to the executor. [VpnBridge] is thread-safe.
 */
class ObsidianVpnService : VpnService() {

    // Single worker. Core thread may time out when idle, so no shutdown is needed in onDestroy.
    private val executor = ThreadPoolExecutor(
        1,
        1,
        30L,
        TimeUnit.SECONDS,
        LinkedBlockingQueue<Runnable>(),
        ThreadFactory { runnable -> Thread(runnable, "obsidian-vpn") },
    ).apply { allowCoreThreadTimeOut(true) }

    // Executor-confined.
    private var sessionId: String? = null
    private var generationCounter = 0L

    // Read from Go and main threads. activeGeneration 0 means no live session: stale callbacks are ignored.
    @Volatile
    private var activeGeneration = 0L

    @Volatile
    private var sessionName = ""

    @Volatile
    private var connectedAtMs: Long? = null

    @Volatile
    private var lastStatsAt = 0L

    // Id of the newest onStartCommand. stopSelfResult(id) only stops the service when no newer start
    // arrived, so a quick disconnect followed by connect cannot kill the service under the new start.
    @Volatile
    private var lastStartId = 0

    // Set in onDestroy. Queued executor tasks must not build a tunnel in a dead service.
    @Volatile
    private var destroyed = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        val action = intent?.action
        when {
            intent != null && action == ACTION_START -> startRequested(intent, startId)
            intent != null && action == ACTION_STOP -> executor.execute { disconnectInternal(startId) }
            // System start with no app intent (always-on, a sticky restart, or an unknown intent) while
            // nothing runs. An active session is left alone.
            !VpnBridge.isActive -> systemStart(startId)
        }
        // Sticky only while a session is live or being started. A restart then rebuilds the tunnel
        // through systemStart. An idle or stopped service must not come back on its own.
        val sessionWanted = VpnBridge.isActive || action == ACTION_START
        return if (sessionWanted) START_STICKY else START_NOT_STICKY
    }

    private fun startRequested(intent: Intent, startId: Int) {
        val request = requestFromIntent(intent)
        if (!promoteOrFail(request?.name.orEmpty(), startId)) return
        if (request == null) {
            executor.execute { disconnectInternal(startId) }
        } else {
            executor.execute { startSession(request, startId) }
        }
    }

    /**
     * System start without an app intent. Rebuilds the tunnel from the last successful connect. With
     * no saved request (the app was never connected, or the file is gone), asks the user to open the
     * app once and stops.
     */
    private fun systemStart(startId: Int) {
        val saved = TunnelStore.load(this)
        if (saved == null) {
            postOpenAppNotice()
            executor.execute { teardownAndExit(startId) }
            return
        }
        if (promoteOrFail(saved.name, startId)) {
            executor.execute { startSession(saved, startId) }
        }
    }

    /**
     * Promotes the service to foreground. startForegroundService requires startForeground within
     * 5 seconds, so this runs first. On failure it reports the error and returns false.
     */
    private fun promoteOrFail(name: String, startId: Int): Boolean {
        return try {
            promoteToForeground(getString(R.string.vpn_notification_connecting, name))
            true
        } catch (e: Exception) {
            // Foreground start not allowed or the type permission is missing: report instead of crashing.
            val message = e.message ?: e.javaClass.simpleName
            executor.execute { failSession(0L, message, startId) }
            false
        }
    }

    /** Android calls this when the user revokes VPN consent or another VPN takes over. */
    override fun onRevoke() {
        val startId = lastStartId
        executor.execute { disconnectInternal(startId) }
    }

    override fun onDestroy() {
        destroyed = true
        activeGeneration = 0L
        connectedAtMs = null
        // The system can destroy the service without going through disconnectInternal.
        if (VpnBridge.isActive) VpnBridge.publishStatus(VpnBridge.PHASE_DISCONNECTED, 0, null, null)
        executor.execute { teardown() }
        super.onDestroy()
    }

    // ---- session lifecycle (executor thread) ----

    private fun startSession(request: TunnelRequest, startId: Int) {
        if (destroyed) return
        // Invalidate the previous session first, so its late callbacks cannot stop the new one.
        activeGeneration = 0L
        connectedAtMs = null
        teardown()

        val generation = ++generationCounter
        activeGeneration = generation
        sessionName = request.name
        emit(VpnBridge.PHASE_CONNECTING, VpnBridge.STAGE_STARTING, null, "Подготовка туннеля к ${request.serverHost}")

        var tun: ParcelFileDescriptor? = null
        try {
            // Parse here so malformed JSON fails before the TUN interface exists.
            val config = JSONObject(request.configJson)
            val opened = establishTunnel(config, request)
                ?: throw IllegalStateException(getString(R.string.vpn_error_not_prepared))
            tun = opened
            emit(VpnBridge.PHASE_CONNECTING, VpnBridge.STAGE_TUN_READY, null, "VPN-интерфейс создан")

            // Go's tun.OpenFD wraps the fd with os.NewFile, so Go owns it. StopTunnel closes it, and so
            // does a failed session init. Detach so Kotlin never closes it a second time.
            val fd = opened.detachFd()
            tun = null
            sessionId = Mobile.startTunnelWithConfig(
                request.configJson,
                fd.toLong(),
                MTU.toLong(),
                tunnelProtector(),
                statusListener(generation),
                statsListener(generation),
            )
            // Only a session that started is remembered, so always-on restores the last working config.
            if (!TunnelStore.save(this, request)) {
                VpnBridge.publishLog("Автоподключение: не удалось сохранить последнее подключение")
            }
        } catch (e: Throwable) {
            // Still ours when the failure happened before detachFd: close it, or the VPN interface stays up.
            try {
                tun?.close()
            } catch (ignored: Exception) {
            }
            failSession(generation, e.message ?: e.javaClass.simpleName, startId)
        }
    }

    private fun failSession(generation: Long, message: String, startId: Int) {
        if (generation == activeGeneration) activeGeneration = 0L
        connectedAtMs = null
        emit(VpnBridge.PHASE_ERROR, 0, message, message)
        teardownAndExit(startId)
    }

    private fun disconnectInternal(startId: Int) {
        activeGeneration = 0L
        connectedAtMs = null
        emit(VpnBridge.PHASE_DISCONNECTED, 0, null, "Отключено")
        teardownAndExit(startId)
    }

    /** Stops the Go session if one exists. Idempotent. The Go side closes the TUN fd. */
    private fun teardown() {
        val id = sessionId ?: return
        sessionId = null
        try {
            Mobile.stopTunnel(id)
        } catch (e: Exception) {
            VpnBridge.publishLog("StopTunnel: ${e.message}")
        }
    }

    /**
     * Stops the Go session and ends the service. Executor thread only. [startId] is the start command
     * this stop belongs to: when a newer start arrived meanwhile, the service stays up for it.
     */
    private fun teardownAndExit(startId: Int) {
        teardown()
        if (stopSelfResult(startId)) stopForeground(STOP_FOREGROUND_REMOVE)
    }

    /**
     * Resolves the server and split hosts, then calls establish(). Runs on the executor, before the
     * tunnel exists, so the lookups use the physical network. Returns null if consent is missing.
     */
    private fun establishTunnel(config: JSONObject, request: TunnelRequest): ParcelFileDescriptor? {
        val routeIps = config.stringList("route_ips")
        val sites = config.stringList("split_sites")
        val entries = (routeIps + sites).distinct()
        val mode = SplitRules.mode(
            config.optString("split_tunnel_mode", ""),
            entries.isNotEmpty(),
            routeIps.isNotEmpty(),
        )
        val parsed = SplitRules.parse(entries)

        val resolved = HostResolver.resolve(parsed.domains + request.serverHost, RESOLVE_BUDGET_MS)
        val serverAddrs = resolved[request.serverHost].orEmpty()
        val domainAddrs = parsed.domains.flatMap { resolved[it].orEmpty() }
        val unresolved = parsed.domains.count { resolved[it].isNullOrEmpty() }
        val dnsAddrs = DNS_SERVERS.mapNotNull { Ipv4.parseCidr(it) }
        val plan = SplitRules.plan(mode, parsed.cidrs, domainAddrs, serverAddrs, dnsAddrs)
        val serverState = if (serverAddrs.isEmpty()) "не резолвится" else "ок"
        VpnBridge.publishLog(
            "Раздельный туннель: $mode, записей ${entries.size}, пропущено ${parsed.skipped}, " +
                "без адреса $unresolved, сервер $serverState",
        )

        val builder = Builder()
            .setSession(request.name.ifBlank { getString(R.string.app_name) })
            .setMtu(MTU)
            .addAddress(TUN_V4, TUN_V4_PREFIX)
        DNS_SERVERS.forEach { builder.addDnsServer(it) }
        // The TUN address is always set. With enable_ipv6=false the Go core answers IPv6 locally
        // (RST / ICMPv6 unreachable), so routing ::/0 into the tunnel blackholes v6 instead of leaking it.
        builder.addAddress(TUN_V6, TUN_V6_PREFIX)
        // The app's own sockets must not be captured. Go's sockets are protected separately.
        builder.addDisallowedApplication(packageName)

        when {
            plan.mode == SplitMode.INCLUDE -> {
                plan.includes.forEach { builder.addRoute(Ipv4.format(it.network), it.prefix) }
                // Include mode: only listed IPv6 networks. No ::/0, so other v6 stays off the tunnel.
                parsed.cidrs6.forEach { builder.addRoute(it.address, it.prefix) }
            }
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> {
                builder.addRoute("0.0.0.0", 0)
                builder.addRoute("::", 0)
                plan.excludes.forEach {
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(Ipv4.format(it.network)), it.prefix))
                }
                parsed.cidrs6.forEach {
                    builder.excludeRoute(IpPrefix(InetAddress.getByName(it.address), it.prefix))
                }
            }
            else -> {
                Ipv4.complement(plan.excludes).forEach { builder.addRoute(Ipv4.format(it.network), it.prefix) }
                // excludeRoute does not exist below API 33, so IPv6 exclusions cannot be expressed here.
                // ::/0 stays routed, which keeps those v6 destinations inside the tunnel.
                builder.addRoute("::", 0)
                if (parsed.cidrs6.isNotEmpty()) {
                    VpnBridge.publishLog("IPv6 исключения требуют Android 13+, IPv6 идёт через туннель целиком")
                }
            }
        }

        return builder.establish()
    }

    // ---- Go callbacks (Go threads) ----

    private fun tunnelProtector(): SocketProtector = object : SocketProtector {
        override fun protect(fd: Long): Boolean = this@ObsidianVpnService.protect(fd.toInt())
    }

    private fun statusListener(generation: Long): StatusListener = object : StatusListener {
        override fun onStatusChange(status: String, detail: String) {
            if (generation != activeGeneration) return
            when (status) {
                "connecting" -> emit(VpnBridge.PHASE_CONNECTING, VpnBridge.STAGE_TUN_READY, null, detail)
                "connected" -> {
                    connectedAtMs = System.currentTimeMillis()
                    emit(VpnBridge.PHASE_CONNECTED, VpnBridge.STAGE_CONNECTED, null, detail)
                }
                "reconnecting" -> {
                    connectedAtMs = null
                    emit(VpnBridge.PHASE_RECONNECTING, VpnBridge.STAGE_TUN_READY, null, detail)
                }
                "disconnected" -> {
                    // Ends when Go stops on its own. Tear down here, unless we already did.
                    activeGeneration = 0L
                    connectedAtMs = null
                    emit(VpnBridge.PHASE_DISCONNECTED, 0, null, detail)
                    val startId = lastStartId
                    executor.execute { teardownAndExit(startId) }
                }
                "error" -> {
                    activeGeneration = 0L
                    connectedAtMs = null
                    emit(VpnBridge.PHASE_ERROR, 0, detail, detail)
                    val startId = lastStartId
                    executor.execute { teardownAndExit(startId) }
                }
                else -> VpnBridge.publishLog(detail)
            }
        }
    }

    private fun statsListener(generation: Long): StatsListener = object : StatsListener {
        override fun onStats(bytesSent: Long, bytesRecv: Long, txSpeed: Long, rxSpeed: Long) {
            if (generation != activeGeneration || !VpnBridge.statsActive) return
            val now = SystemClock.elapsedRealtime()
            if (now - lastStatsAt < STATS_INTERVAL_MS) return
            lastStatsAt = now
            VpnBridge.publishStats(rx = bytesRecv, tx = bytesSent, rxBps = rxSpeed, txBps = txSpeed)
        }
    }

    // ---- status and notification ----

    private fun emit(phase: String, stage: Int, error: String?, detail: String?) {
        VpnBridge.publishStatus(phase, stage, error, connectedAtMs)
        if (!detail.isNullOrBlank()) VpnBridge.publishLog(detail)
        notificationText(phase)?.let { updateNotification(it) }
    }

    private fun notificationText(phase: String): String? {
        val name = sessionName
        return when (phase) {
            VpnBridge.PHASE_CONNECTING -> getString(R.string.vpn_notification_connecting, name)
            VpnBridge.PHASE_CONNECTED -> getString(R.string.vpn_notification_connected, name)
            VpnBridge.PHASE_RECONNECTING -> getString(R.string.vpn_notification_reconnecting, name)
            else -> null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, getString(R.string.vpn_channel_name), NotificationManager.IMPORTANCE_LOW),
        )
        manager.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                getString(R.string.vpn_channel_alert_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }

    /**
     * Asks the user to open the app once, after a system start with no saved config. Uses its own
     * notification id, so it does not clash with the foreground notification.
     */
    private fun postOpenAppNotice() {
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.vpn_notification_open_app))
            .setContentIntent(openAppPendingIntent())
            .setAutoCancel(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(ALERT_NOTIFICATION_ID, notification)
    }

    private fun openAppPendingIntent(): PendingIntent? {
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun promoteToForeground(text: String) {
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun buildNotification(text: String): Notification {
        val openApp = openAppPendingIntent()
        val disconnect = PendingIntent.getService(
            this,
            1,
            Intent(this, ObsidianVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(0, getString(R.string.vpn_notification_disconnect), disconnect)
            .build()
    }

    companion object {
        const val ACTION_START = "com.obsidian.vpn.action.START"
        const val ACTION_STOP = "com.obsidian.vpn.action.STOP"
        const val EXTRA_PROFILE_ID = "profileId"
        const val EXTRA_NAME = "name"
        const val EXTRA_SERVER_HOST = "serverHost"
        const val EXTRA_CONFIG_JSON = "configJson"

        private const val CHANNEL_ID = "vpn"
        private const val NOTIFICATION_ID = 1
        private const val ALERT_CHANNEL_ID = "vpn_alert"
        private const val ALERT_NOTIFICATION_ID = 2
        private const val MTU = 1400
        private const val TUN_V4 = "10.8.0.2"
        private const val TUN_V4_PREFIX = 24
        private const val TUN_V6 = "fd00:8::2"
        private const val TUN_V6_PREFIX = 64
        private val DNS_SERVERS = listOf("1.1.1.1", "8.8.8.8")
        private const val RESOLVE_BUDGET_MS = 2_000L
        private const val STATS_INTERVAL_MS = 1_000L

        fun start(context: Context, request: TunnelRequest) {
            val intent = Intent(context, ObsidianVpnService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_PROFILE_ID, request.profileId)
                .putExtra(EXTRA_NAME, request.name)
                .putExtra(EXTRA_SERVER_HOST, request.serverHost)
                .putExtra(EXTRA_CONFIG_JSON, request.configJson)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.startService(Intent(context, ObsidianVpnService::class.java).setAction(ACTION_STOP))
        }

        fun requestFromIntent(intent: Intent): TunnelRequest? {
            val profileId = intent.getStringExtra(EXTRA_PROFILE_ID) ?: return null
            val name = intent.getStringExtra(EXTRA_NAME) ?: return null
            val serverHost = intent.getStringExtra(EXTRA_SERVER_HOST) ?: return null
            val configJson = intent.getStringExtra(EXTRA_CONFIG_JSON) ?: return null
            return TunnelRequest(profileId, name, serverHost, configJson)
        }
    }
}

private fun JSONObject.stringList(key: String): List<String> {
    val array: JSONArray = optJSONArray(key) ?: return emptyList()
    return (0 until array.length()).mapNotNull { index ->
        array.optString(index, "").trim().takeIf { it.isNotEmpty() }
    }
}
