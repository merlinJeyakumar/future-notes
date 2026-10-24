package com.nativedevps.futurenotes

import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Content-free diagnostics. Never accept exception messages, IDs, URIs or paths. */
object MobileDiagnostics {
    enum class Event {
        ENGINE_CREATED, ENGINE_REUSED, ACTIVITY_CREATED, ACTIVITY_DESTROYED,
        ACTIVITY_RESUMED, ACTIVITY_PAUSED, CONFIGURATION, MEMORY_PRESSURE,
        CAPACITY_LIMIT, JOB_PHASES, JOB_HOST_FAILED, SERVICE_STARTED,
        SERVICE_STOPPED, SERVICE_TIMEOUT, CANCEL_REQUESTED, PERMISSION_RESULT,
        DART_STARTED, DART_STARTUP_FAILED, DART_FRAMEWORK_ERROR, DART_ASYNC_ERROR,
        DART_LIFECYCLE, DART_METRICS, DART_MEMORY_PRESSURE,
        DRAFT_READ_FAILED, DRAFT_WRITE_FAILED, DRAFT_RECOVERED,
        JOB_RECORD_FAILED, JOB_CHANNEL_FAILED, DART_JOB_PHASE, VIEWER_FAILED,
        CIPHER_IO, CIPHER_FAILED, DISCOVERY_FAILED, THUMBNAIL_READY, THUMBNAIL_FAILED
    }
    fun record(event: Event, vararg fields: Pair<String, Number>) {
        val value = JSONObject().put("event", event.name).put("uptime_ms", SystemClock.elapsedRealtime())
        for ((key, number) in fields.take(12)) {
            if (key.matches(Regex("[a-z_]{1,32}")) && number.toDouble().isFinite()) value.put(key, number)
        }
        Log.i("FutureNotes", value.toString())
    }
    fun bind(messenger: BinaryMessenger) {
        MethodChannel(messenger, "future_notes/diagnostics").setMethodCallHandler { call, result ->
            val event = call.argument<String>("event")
            // Dart can emit only its fixed event set and numeric measurements.
            val allowed = setOf("DART_STARTED", "DART_STARTUP_FAILED", "DART_FRAMEWORK_ERROR", "DART_ASYNC_ERROR",
                "DART_LIFECYCLE", "DART_METRICS", "DART_MEMORY_PRESSURE", "DRAFT_READ_FAILED", "DRAFT_WRITE_FAILED",
                "DRAFT_RECOVERED", "JOB_RECORD_FAILED", "JOB_CHANNEL_FAILED", "DART_JOB_PHASE", "VIEWER_FAILED", "DISCOVERY_FAILED")
            if (call.method != "record" || event !in allowed) { result.notImplemented(); return@setMethodCallHandler }
            val fields = call.argument<Map<String, Any?>>("metrics") ?: emptyMap()
            record(Event.valueOf(event!!), *fields.entries.take(12).mapNotNull { (key, value) ->
                (value as? Number)?.let { key to it }
            }.toTypedArray())
            result.success(null)
        }
    }
}
