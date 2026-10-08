package com.obsidian.vpn

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge between Dart (obsidian/vpn) and the VPN service. FlutterActivity is a plain Activity,
 * so consent and permission results use the Activity callbacks instead of AndroidX launchers.
 */
class MainActivity : FlutterActivity() {

    private var pendingPrepare: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            handle(call, result)
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                VpnBridge.attach(events)
            }

            override fun onCancel(arguments: Any?) {
                VpnBridge.detach()
            }
        })
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> prepare(result)
            "connect" -> connect(call, result)
            "disconnect" -> guardedStart(result) { ObsidianVpnService.stop(this) }
            "applySplit" -> applySplit(call, result)
            "setStatsActive" -> {
                VpnBridge.statsActive = call.argument<Boolean>("active") == true
                result.success(null)
            }
            "currentStatus" -> result.success(VpnBridge.currentStatus())
            "openSystemVpnSettings" -> openSystemVpnSettings(result)
            else -> result.notImplemented()
        }
    }

    // ---- system VPN settings: the user enables "always-on" and "block without VPN" there ----

    private fun openSystemVpnSettings(result: MethodChannel.Result) {
        val intent = Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("settings_unavailable", e.message ?: "no VPN settings activity", null)
        }
    }

    // ---- prepare: notification permission (API 33+), then VpnService consent ----

    private fun prepare(result: MethodChannel.Result) {
        if (pendingPrepare != null) {
            result.error("busy", "VPN consent request is already open", null)
            return
        }
        pendingPrepare = result
        val needsNotifications = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        if (needsNotifications) {
            // The answer does not matter for the tunnel: it still runs without a notification.
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        } else {
            continuePrepare()
        }
    }

    @Suppress("DEPRECATION")
    private fun continuePrepare() {
        val pending = pendingPrepare ?: return
        val consent: Intent? = VpnService.prepare(this)
        if (consent == null) {
            pendingPrepare = null
            pending.success(true)
        } else {
            startActivityForResult(consent, REQUEST_VPN_CONSENT)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_VPN_CONSENT) {
            val granted = resultCode == RESULT_OK
            pendingPrepare?.success(granted)
            pendingPrepare = null
        }
    }

    @Suppress("DEPRECATION")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATIONS) continuePrepare()
    }

    // ---- connect / applySplit ----

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val request = requestFrom(call)
        if (request == null) {
            result.error("bad_args", "profileId, name, serverHost and configJson are required", null)
            return
        }
        if (VpnService.prepare(this) != null) {
            result.error("not_prepared", "VPN consent has not been granted", null)
            return
        }
        guardedStart(result) {
            VpnBridge.lastRequest = request
            ObsidianVpnService.start(this, request)
        }
    }

    private fun applySplit(call: MethodCall, result: MethodChannel.Result) {
        val configJson = call.argument<String>("configJson")
        if (configJson == null) {
            result.error("bad_args", "configJson is required", null)
            return
        }
        val current = VpnBridge.lastRequest
        if (current == null || !VpnBridge.isActive) {
            // Nothing is running. The next connect sends the new config.
            result.success(null)
            return
        }
        // Restart with the new config: the service tears the old session down first.
        val updated = current.copy(configJson = configJson)
        guardedStart(result) {
            VpnBridge.lastRequest = updated
            ObsidianVpnService.start(this, updated)
        }
    }

    private fun requestFrom(call: MethodCall): TunnelRequest? {
        val profileId = call.argument<String>("profileId") ?: return null
        val name = call.argument<String>("name") ?: return null
        val serverHost = call.argument<String>("serverHost") ?: return null
        val configJson = call.argument<String>("configJson") ?: return null
        return TunnelRequest(profileId, name, serverHost, configJson)
    }

    /** Runs a service call and answers the Dart result. A failed start becomes service_error. */
    private inline fun guardedStart(result: MethodChannel.Result, block: () -> Unit) {
        try {
            block()
            result.success(null)
        } catch (e: Exception) {
            // IllegalStateException when the app is in the background (Android 12+ FGS limits).
            result.error("service_error", e.message ?: "unknown error", null)
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "obsidian/vpn"
        private const val EVENT_CHANNEL = "obsidian/vpn/events"
        private const val REQUEST_VPN_CONSENT = 4101
        private const val REQUEST_NOTIFICATIONS = 4102
    }
}
