package com.nativedevps.futurenotes

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Holds the existing runtime only. Never launches a second Flutter engine. */
class AttachmentJobService : Service() {
    private var wake: android.os.PowerManager.WakeLock? = null
    private var foregroundCount: Int? = null
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!running) MobileDiagnostics.record(MobileDiagnostics.Event.SERVICE_STARTED)
        val host = (application as FutureNotesApplication).jobHostOrNull()
        if (host == null) { stopSelf(); return START_NOT_STICKY }
        if (intent?.action == CANCEL) host.cancelSafeJobs()
        if (intent?.action == CANCEL_JOB) host.cancelJob(intent.getStringExtra(JobNotifications.JOB_ID))
        if (host.jobs.isEmpty()) { stopSelf(); return START_NOT_STICKY }
        if (foregroundCount != host.jobs.size) {
            val summary = host.foregroundNotification()
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, summary, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(NOTIFICATION, summary)
            foregroundCount = host.jobs.size
        }
        if (wake == null) wake = getSystemService(android.os.PowerManager::class.java).newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "$packageName:attachments").apply { setReferenceCounted(false) }
        // Bounded lease, renewed only by the existing active-job heartbeat.
        wake?.acquire(60_000L)
        running = true
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) {
        MobileDiagnostics.record(MobileDiagnostics.Event.SERVICE_TIMEOUT)
        (application as FutureNotesApplication).jobHostOrNull()?.timeout()
        stopSelf()
    }
    override fun onDestroy() {
        MobileDiagnostics.record(MobileDiagnostics.Event.SERVICE_STOPPED)
        if (wake?.isHeld == true) wake?.release()
        wake = null; running = false; foregroundCount = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        (application as FutureNotesApplication).jobHostOrNull()?.refreshNotifications()
        super.onDestroy()
    }
    companion object {
        const val CHANNEL = "future-notes-jobs"
        const val CANCEL = "future_notes.cancel_safe_jobs"
        const val CANCEL_JOB = "future_notes.cancel_job"
        const val NOTIFICATION = 24082
        var running = false
            private set
    }
}
