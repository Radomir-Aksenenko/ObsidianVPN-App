package com.obsidian.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Process-wide hub between [ObsidianVpnService] (producer, any thread) and the EventChannel sink
 * owned by [MainActivity]. The sink is touched only on the main thread.
 *
 * Event maps match the protocol in app-docs/ARCHITECTURE.md ("Native channel protocol").
 */
object VpnBridge {
    const val PHASE_DISCONNECTED = "disconnected"
    const val PHASE_CONNECTING = "connecting"
    const val PHASE_CONNECTED = "connected"
    const val PHASE_RECONNECTING = "reconnecting"
    const val PHASE_ERROR = "error"

    // Stage 2 (handshake done) is not reported by the Go core, so it is skipped.
    const val STAGE_STARTING = 1
    const val STAGE_TUN_READY = 3
    const val STAGE_CONNECTED = 4

    private val main = Handler(Looper.getMainLooper())
    @Volatile
    private var sink: EventChannel.EventSink? = null

    /** Set from Dart. Stats are produced only while this is true. */
    @Volatile
    var statsActive: Boolean = false

    /** The request of the last connect or applySplit, reused by applySplit. */
    @Volatile
    var lastRequest: TunnelRequest? = null

    @Volatile
    private var status: Map<String, Any?> = statusEvent(PHASE_DISCONNECTED, 0, null, null)

    val isActive: Boolean
        get() {
            val phase = status["phase"] as? String
            return phase == PHASE_CONNECTING || phase == PHASE_CONNECTED || phase == PHASE_RECONNECTING
        }

    fun currentStatus(): Map<String, Any?> = status

    /** Called on the main thread by the EventChannel handler. Sends the current status first. */
    fun attach(events: EventChannel.EventSink) {
        main.post {
            sink = events
            events.success(status)
        }
    }

    /** Drops [events] only. A late cancel of an old listener must not remove a newer one. */
    fun detach(events: EventChannel.EventSink) {
        main.post { if (sink === events) sink = null }
    }

    /** The Flutter engine is going away: nothing may be sent to its sink any more. */
    fun detachAll() {
        main.post { sink = null }
    }

    fun publishStatus(phase: String, stage: Int, error: String?, connectedAtMs: Long?) {
        val event = statusEvent(phase, stage, error, connectedAtMs)
        status = event
        dispatch(event)
    }

    fun publishLog(line: String) {
        dispatch(mapOf("type" to "log", "line" to line))
    }

    fun publishStats(rx: Long, tx: Long, rxBps: Long, txBps: Long) {
        if (!statsActive || sink == null) return
        dispatch(mapOf("type" to "stats", "rx" to rx, "tx" to tx, "rxBps" to rxBps, "txBps" to txBps))
    }

    private fun statusEvent(phase: String, stage: Int, error: String?, connectedAtMs: Long?): Map<String, Any?> =
        mapOf(
            "type" to "status",
            "phase" to phase,
            "stage" to stage,
            "error" to error,
            "connectedAtMs" to connectedAtMs,
        )

    private fun dispatch(event: Map<String, Any?>) {
        main.post {
            val target = sink ?: return@post
            try {
                target.success(event)
            } catch (e: RuntimeException) {
                // The Flutter engine is detaching. The next attach replays the current status.
            }
        }
    }
}
