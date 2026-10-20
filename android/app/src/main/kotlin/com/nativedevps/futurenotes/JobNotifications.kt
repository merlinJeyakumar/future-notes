package com.nativedevps.futurenotes

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** Per-job UI only. Job ownership and all mutations remain in the Dart coordinator. */
class JobNotifications(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val updates = NotificationUpdateQueue<Pair<Map<String, Any?>, Boolean>>()
    private var scheduled = false
    private var lastPost = -UPDATE_INTERVAL
    private var interruptedSummaryIds: Set<String>? = null
    private val publishNext = object : Runnable {
        override fun run() {
            scheduled = false
            val (id, record) = updates.take() ?: return
            postJob(id, record.first, record.second)
            lastPost = SystemClock.elapsedRealtime()
            scheduleUpdate()
        }
    }

    private fun scheduleUpdate() {
        if (scheduled || !updates.hasPending) return
        scheduled = true
        handler.postDelayed(publishNext, (UPDATE_INTERVAL - (SystemClock.elapsedRealtime() - lastPost)).coerceAtLeast(0))
    }

    private fun builder(): Notification.Builder {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Attachment processing", NotificationManager.IMPORTANCE_LOW))
        }
        return (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context))
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOnlyAlertOnce(true).setShowWhen(false)
            .setGroup(GROUP)
            .apply { if (Build.VERSION.SDK_INT >= 26) setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY) }
            // Android 12 may defer service notifications; show user-started
            // attachment work immediately, without changing channel settings.
            .apply { if (Build.VERSION.SDK_INT >= 31) setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE) }
            .setVisibility(Notification.VISIBILITY_SECRET)
    }

    private fun open(id: String? = null): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (id != null) {
            intent.action = OPEN_JOB
            intent.data = Uri.Builder().scheme("future-notes-job").authority("open").appendPath(id).build()
            intent.putExtra(JOB_ID, id)
        }
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun summary(count: Int, ongoing: Boolean): Notification = builder()
        .setContentTitle(context.applicationInfo.loadLabel(context.packageManager))
        .setContentText(if (ongoing) "$count active job(s)" else "$count interrupted job(s)")
        .setGroupSummary(true).setOngoing(ongoing).setContentIntent(open()).build()

    private fun dismiss(ids: List<String>): PendingIntent {
        val identity = ids.sorted().joinToString(",")
        val intent = Intent(context, InterruptedJobDismissal::class.java)
            .setAction(InterruptedJobDismissal.ACTION)
            .setData(Uri.Builder().scheme("future-notes-job").authority("dismiss").appendPath(identity).build())
            .putStringArrayListExtra(InterruptedJobDismissal.IDS, ArrayList(ids))
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun sync(active: List<Map<String, Any?>>, interrupted: List<Map<String, Any?>>) {
        val records = linkedMapOf<String, Pair<Map<String, Any?>, Boolean>>()
        for (job in interrupted.filter { it["notificationDismissed"] != true }) (job["id"] as? String)?.let { records[it] = job to false }
        for (job in active) (job["id"] as? String)?.let { records[it] = job to true }
        val tags = records.keys.map { TAG + it }.toSet()
        // Tagged identities avoid hash collisions and allow stale cleanup after process death.
        for (notification in manager.activeNotifications) {
            if (notification.id == CHILD && notification.tag?.startsWith(TAG) == true && notification.tag !in tags) {
                manager.cancel(notification.tag, CHILD)
            }
        }
        updates.replace(records)
        if (!updates.hasPending) {
            handler.removeCallbacks(publishNext)
            scheduled = false
        } else scheduleUpdate()
        if (active.isEmpty()) {
            if (records.isEmpty()) {
                manager.cancel(SUMMARY)
                interruptedSummaryIds = null
            } else if (interruptedSummaryIds != records.keys || manager.activeNotifications.none { it.id == SUMMARY && it.tag == null }) {
                try {
                    manager.notify(SUMMARY, builder()
                        .setContentTitle(context.applicationInfo.loadLabel(context.packageManager))
                        .setContentText("${records.size} interrupted task(s)")
                        .setGroupSummary(true).setOngoing(false).setContentIntent(open())
                        .setDeleteIntent(dismiss(records.keys.toList())).build())
                    interruptedSummaryIds = records.keys.toSet()
                } catch (_: SecurityException) { /* Recovery remains available in the app. */ }
            }
        } else interruptedSummaryIds = null
    }

    private fun postJob(id: String, job: Map<String, Any?>, running: Boolean) {
        val title = (job["fileName"] as? String)?.take(256)?.takeIf { it.isNotBlank() } ?: "Attachment operation"
        val detail = (job["detail"] as? String)?.take(256)?.takeIf { it.isNotBlank() }
        val notification = builder().setContentTitle(title)
            .setContentText(if (running) "${operation(job["operation"])} · ${detail ?: phase(job["phase"])}" else "Interrupted · Tap to review recovery")
            .setContentIntent(open(id)).setOngoing(running).setAutoCancel(false)
        if (running) {
            val total = (job["total"] as? Number)?.toLong()?.coerceAtLeast(0) ?: 0L
            val done = (job["bytes"] as? Number)?.toLong()?.coerceAtLeast(0) ?: 0L
            val fileTotal = (job["currentTotal"] as? Number)?.toLong() ?: 0L
            val fileDone = (job["currentBytes"] as? Number)?.toLong() ?: 0L
            if (total > 0) {
                fun metric(bytes: Long, size: Long): String {
                    val percent = (bytes.toDouble() / size * 100).coerceIn(0.0, 100.0).toInt()
                    return "${android.text.format.Formatter.formatShortFileSize(context, bytes)} / ${android.text.format.Formatter.formatShortFileSize(context, size)} · $percent%"
                }
                val current = if (fileTotal > 0) "\nCurrent file: ${metric(fileDone, fileTotal)}" else ""
                notification.setStyle(Notification.BigTextStyle().bigText(
                    "${operation(job["operation"])} · ${detail ?: phase(job["phase"])}$current\nOverall: ${metric(done, total)}"))
            }
            notification.setProgress(1000, if (total > 0) ((done.toDouble() / total).coerceIn(0.0, 1.0) * 1000).toInt() else 0, total == 0L)
            if (job["cancellable"] == true) {
                val intent = Intent(context, AttachmentJobService::class.java).setAction(AttachmentJobService.CANCEL_JOB)
                    .setData(Uri.Builder().scheme("future-notes-job").authority("cancel").appendPath(id).build())
                    .putExtra(JOB_ID, id)
                val cancel = PendingIntent.getService(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                notification.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancel)
            }
        } else {
            val dismissal = dismiss(listOf(id))
            notification.setDeleteIntent(dismissal)
                .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissal)
        }
        try { manager.notify(TAG + id, CHILD, notification.build()) }
        catch (_: SecurityException) { /* Per-job in-app access remains available. */ }
    }

    private fun operation(value: Any?): String = when (value) {
        "add" -> "Attach"; "open" -> "Open"; "protection" -> "Protection"
        "export" -> "Export"; "import" -> "Import"; else -> "Attachment"
    }
    private fun phase(value: Any?): String = when (value) {
        "queued" -> "Queued"; "preparing" -> "Preparing"; "decrypting" -> "Decrypting"
        "encrypting" -> "Encrypting"; "verifying" -> "Verifying"
        "finalizing" -> "Finishing safely"; "cancelling" -> "Cancelling"; else -> "Processing"
    }
    companion object {
        private const val UPDATE_INTERVAL = 500L
        const val CHANNEL = "future-notes-jobs"
        const val GROUP = "future-notes-work"
        const val TAG = "future-notes-job:"
        const val CHILD = 24084
        const val SUMMARY = 24082
        const val OPEN_JOB = "future_notes.open_job"
        const val JOB_ID = "future_notes.job_id"
    }
}
