package com.nativedevps.futurenotes

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.File

class AndroidJobHost(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "future_notes/jobs")
    private val ledger = AtomicFile(File(context.noBackupFilesDir, "future-notes-jobs.json"))
    private val interrupted = AtomicFile(File(context.noBackupFilesDir, "future-notes-interrupted-jobs.json"))
    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private var lastLedger = ""
    private var lastWrite = 0L
    private var lastControl = ""
    private var recoveredLedger = false
    private val notifications = JobNotifications(context)
    private var retainedJobs: List<Map<String, Any?>> = emptyList()
    private var pendingNotification: String? = null
    private var priorCpu = 0L
    private var priorTime = 0L
    private var priorTotal = 0L
    private var priorIdle = 0L
    private var pressureUntil = 0L
    private var pressureTier = 0
    private var lastLimit = -1
    private var lastPhases: Map<String, Int> = emptyMap()
    private var lastServiceStart = 0L
    private var serviceCount = -1
    var jobs: List<Map<String, Any?>> = emptyList()
        private set
    fun attach(host: Activity) { activity = host }
    fun detach(host: Activity) { if (activity === host) activity = null }
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "capacity" -> result.success(capacity())
                    "update" -> {
                        val incoming = call.argument<List<Map<String, Any?>>>("jobs") ?: emptyList()
                        if (incoming.size > 10000 || incoming.any { it["id"] !is String || (it["id"] as String).length > 128 || it["phase"] !is String }) throw IllegalArgumentException()
                        jobs = incoming.map { mapOf("id" to it["id"], "phase" to it["phase"], "detail" to (it["detail"] as? String)?.take(256), "cancellable" to (it["cancellable"] == true), "operation" to it["operation"], "fileName" to it["fileName"], "bytes" to it["bytes"], "total" to it["total"], "currentBytes" to it["currentBytes"], "currentTotal" to it["currentTotal"], "recovery" to it["recovery"]) }
                        val phases = jobs.groupingBy { it["phase"] as String }.eachCount()
                        if (phases != lastPhases) {
                            lastPhases = phases
                            val known = listOf("queued", "preparing", "decrypting", "encrypting", "verifying", "finalizing", "cancelling", "failed")
                            MobileDiagnostics.record(MobileDiagnostics.Event.JOB_PHASES, "active" to jobs.size,
                                *known.map { it to (phases[it] ?: 0) }.toTypedArray())
                        }
                        persist()
                        if (jobs.isNotEmpty() && Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            val host = activity
                            if (pending != null || host == null) { result.error("notification_permission", "Enable notifications to continue attachment work in the background.", null) }
                            else { pending = result; host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION) }
                        } else { updateService(); result.success(capacity()) }
                    }
                    "interruptedJobs" -> {
                        val records = linkedMapOf<String, org.json.JSONObject>()
                        for (record in if (recoveredLedger) listOf(interrupted) else listOf(interrupted, ledger)) {
                            val bytes = try { record.openRead().use { if (it.channel.size() > 2 * 1024 * 1024) throw IllegalStateException(); it.readBytes() } } catch (_: java.io.FileNotFoundException) { null }
                            if (bytes != null) { val array = JSONArray(bytes.toString(Charsets.UTF_8)); for (i in 0 until array.length()) { val value = array.getJSONObject(i); records[value.getString("id")] = value } }
                        }
                        val encoded = JSONArray(records.values.toList()).toString().toByteArray(Charsets.UTF_8)
                        if (encoded.size > 2 * 1024 * 1024) throw IllegalStateException()
                        val output = interrupted.startWrite()
                        try { output.write(encoded); interrupted.finishWrite(output) } catch (error: Exception) { interrupted.failWrite(output); throw error }
                        recoveredLedger = true
                        retainedJobs = records.values.map { json -> json.keys().asSequence().associateWith { key -> json.opt(key).takeUnless { it == org.json.JSONObject.NULL } } }
                        refreshNotifications()
                        result.success(encoded.toString(Charsets.UTF_8))
                    }
                    "acknowledgeInterrupted" -> {
                        val ids = call.argument<List<String>>("ids") ?: throw IllegalArgumentException()
                        val safe = ids.filter { id -> jobs.none { it["id"] == id } }
                        InterruptedJobDismissal.remove(context, safe)
                        retainedJobs = retainedJobs.filter { it["id"] !in safe }
                        refreshNotifications()
                        channel.invokeMethod("interruptedJobsChanged", JSONArray(retainedJobs).toString())
                        result.success(null)
                    }
                    "dismissInterruptedNotification" -> {
                        dismissInterrupted(call.argument<List<String>>("ids") ?: throw IllegalArgumentException())
                        result.success(null)
                    }
                    "takeNotification" -> {
                        val id = pendingNotification
                        pendingNotification = null
                        result.success(id)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                MobileDiagnostics.record(MobileDiagnostics.Event.JOB_HOST_FAILED)
                result.error("job_host_failed", "Background processing could not be started. Keep the app open and retry.", null)
            }
        }
    }
    private fun persist() {
        val data = JSONArray(jobs).toString()
        if (data.toByteArray(Charsets.UTF_8).size > 2 * 1024 * 1024) throw IllegalStateException()
        val now = android.os.SystemClock.elapsedRealtime()
        val control = JSONArray(jobs.map { mapOf("id" to it["id"], "phase" to it["phase"], "recovery" to it["recovery"]) }).toString()
        if (control == lastControl && now - lastWrite < 5000) return
        val output = ledger.startWrite()
        try { output.write(data.toByteArray(Charsets.UTF_8)); ledger.finishWrite(output); lastLedger = data; lastControl = control; lastWrite = now }
        catch (error: Exception) { ledger.failWrite(output); throw error }
    }
    fun dismissInterrupted(ids: List<String>) {
        val safe = ids.filter { id -> jobs.none { it["id"] == id } }
        InterruptedJobDismissal.hide(context, safe)
        retainedJobs = retainedJobs.map { if (it["id"] in safe) it + ("notificationDismissed" to true) else it }
        refreshNotifications()
        channel.invokeMethod("interruptedJobsChanged", JSONArray(retainedJobs).toString())
    }
    private fun updateService() {
        val intent = Intent(context, AttachmentJobService::class.java)
        val now = android.os.SystemClock.elapsedRealtime()
        if (jobs.isEmpty()) {
            if (serviceCount != -1 || AttachmentJobService.running) context.stopService(intent)
            serviceCount = -1
        } else if (!AttachmentJobService.running || serviceCount != jobs.size || now - lastServiceStart >= 20_000L) {
            if (Build.VERSION.SDK_INT >= 26 && !AttachmentJobService.running) context.startForegroundService(intent)
            else context.startService(intent)
            serviceCount = jobs.size
            lastServiceStart = now
        }
        refreshNotifications()
    }
    fun refreshNotifications() { notifications.sync(jobs, retainedJobs) }
    fun foregroundNotification() = notifications.summary(jobs.size, true)
    fun notificationIntent(intent: Intent?) {
        if (intent?.action != JobNotifications.OPEN_JOB) return
        val id = intent.getStringExtra(JobNotifications.JOB_ID) ?: return
        if (id.isBlank() || id.length > 128) return
        // IDs select existing coordinator records, never filesystem paths.
        pendingNotification = id
        intent.removeExtra(JobNotifications.JOB_ID)
        intent.action = null
        channel.invokeMethod("jobNotification", null)
    }
    fun cancelJob(id: String?) {
        if (id != null && jobs.any { it["id"] == id && it["cancellable"] == true }) {
            MobileDiagnostics.record(MobileDiagnostics.Event.CANCEL_REQUESTED, "individual" to 1)
            channel.invokeMethod("cancelJob", mapOf("id" to id))
        }
        refreshNotifications() // Remove stale actions when the job has already settled.
    }
    fun permissionResult(request: Int, results: IntArray): Boolean {
        if (request != REQUEST_NOTIFICATION) return false
        val result = pending
        pending = null
        MobileDiagnostics.record(MobileDiagnostics.Event.PERMISSION_RESULT,
            "granted" to if (results.firstOrNull() == PackageManager.PERMISSION_GRANTED) 1 else 0)
        if (results.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            try { updateService(); result?.success(capacity()) }
            catch (_: Exception) { result?.error("job_host_failed", "Background service start was denied.", null); cancelSafeJobs() }
        } else { result?.error("notification_permission", "Notification permission was denied. Background jobs were cancelled safely.", null); cancelSafeJobs() }
        return true
    }
    fun cancelSafeJobs() { channel.invokeMethod("cancelSafeJobs", null) }
    fun timeout() { channel.invokeMethod("timeout", null) }
    fun memoryPressure(level: Int) {
        val tier = when (level) {
            15, 80 -> 2
            5, 10, 40, 60 -> 1
            else -> 0 // UI_HIDDEN alone is not memory pressure.
        }
        if (tier > 0) {
            val now = android.os.SystemClock.elapsedRealtime()
            pressureTier = if (now < pressureUntil) maxOf(pressureTier, tier) else tier
            // Callbacks have no corresponding "pressure ended" event. Reassess
            // live telemetry after this bounded cooldown; never suspend forever.
            pressureUntil = now + 15_000L
        }
        MobileDiagnostics.record(MobileDiagnostics.Event.MEMORY_PRESSURE, "level" to level, "tier" to tier)
        channel.invokeMethod("memoryPressure", capacity())
    }
    private fun capacity(): Map<String, Any> {
        val memory = ActivityManager.MemoryInfo()
        val manager = context.getSystemService(ActivityManager::class.java)
        manager.getMemoryInfo(memory)
        val cores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        val now = android.os.SystemClock.elapsedRealtime()
        val cpu = android.os.Process.getElapsedCpuTime()
        val process = if (priorTime == 0L || now <= priorTime) 0.0 else ((cpu - priorCpu).toDouble() / ((now - priorTime) * cores)).coerceIn(0.0, 1.0)
        priorCpu = cpu; priorTime = now
        var detected = false
        var system = process
        try {
            val fields = File("/proc/stat").useLines { it.first().trim().split(Regex("\\s+")).drop(1).take(8).map(String::toLong) }
            val total = fields.sum(); val idle = fields[3] + fields[4]
            if (priorTotal != 0L && total > priorTotal) { system = (1.0 - (idle - priorIdle).toDouble() / (total - priorTotal)).coerceIn(0.0, 1.0); detected = true }
            priorTotal = total; priorIdle = idle
        } catch (_: Exception) { /* Restricted procfs keeps the conservative worker path. */ }
        val power = context.getSystemService(android.os.PowerManager::class.java)
        val thermal = if (Build.VERSION.SDK_INT >= 29) power.currentThermalStatus else 0
        val runtime = Runtime.getRuntime()
        val managedUsed = runtime.totalMemory() - runtime.freeMemory()
        val managedHeadroom = (runtime.maxMemory() - managedUsed - 16L * 1024 * 1024).coerceAtLeast(0)
        // The memory class is a work-budget allowance, not a hard limit on the
        // combined Dart/native heaps. Leave headroom for editor and preview work.
        val appAllowance = manager.memoryClass.toLong() * 1024 * 1024 / 2
        val systemHeadroom = (memory.availMem - memory.threshold).coerceAtLeast(0)
        val available = minOf(systemHeadroom, managedHeadroom, appAllowance)
        val pressure = if (memory.lowMemory || available == 0L) 2 else if (now < pressureUntil) pressureTier else 0
        val limit = when { pressure >= 2 -> 2; pressure > 0 || available < 64L * 1024 * 1024 -> 1; else -> 0 }
        if (limit != lastLimit) {
            lastLimit = limit
            MobileDiagnostics.record(MobileDiagnostics.Event.CAPACITY_LIMIT, "limit" to limit,
                "available_mib" to available / (1024 * 1024), "managed_mib" to managedUsed / (1024 * 1024),
                "native_mib" to android.os.Debug.getNativeHeapAllocatedSize() / (1024 * 1024), "thermal" to thermal)
        }
        return mapOf("processors" to cores, "availableBytes" to available, "workerBytes" to if (AndroidCipher.available) 16L * 1024 * 1024 else 64L * 1024 * 1024,
            "processCpu" to process, "systemCpu" to system, "thermal" to thermal, "detected" to detected, "memoryPressure" to pressure)
    }
    companion object { const val REQUEST_NOTIFICATION = 24083 }
}
