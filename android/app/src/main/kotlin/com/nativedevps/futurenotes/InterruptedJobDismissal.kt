package com.nativedevps.futurenotes

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.AtomicFile
import org.json.JSONArray
import java.io.File

/** Dismisses notification records only; never removes recovery/library objects. */
class InterruptedJobDismissal : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val ids = intent.getStringArrayListExtra(IDS) ?: return
        try {
            val host = (context.applicationContext as FutureNotesApplication).jobHostOrNull()
            if (host != null) host.dismissInterrupted(ids)
            else {
                // A notification swipe must not create an engine or a writer.
                hide(context, ids)
                JobNotifications(context).sync(emptyList(), read(context, "future-notes-interrupted-jobs.json"))
            }
        } catch (_: Exception) {
            MobileDiagnostics.record(MobileDiagnostics.Event.JOB_HOST_FAILED)
        }
    }

    companion object {
        const val ACTION = "future_notes.dismiss_interrupted_job"
        const val IDS = "future_notes.dismiss_ids"
        private fun file(context: Context, name: String) = AtomicFile(File(context.noBackupFilesDir, name))
        private fun read(context: Context, name: String): List<Map<String, Any?>> {
            val bytes = try { file(context, name).openRead().use {
                require(it.channel.size() <= 2 * 1024 * 1024); it.readBytes()
            } } catch (_: java.io.FileNotFoundException) { return emptyList() }
            val array = JSONArray(bytes.toString(Charsets.UTF_8))
            return (0 until array.length()).map { index ->
                val json = array.getJSONObject(index)
                json.keys().asSequence().associateWith { key -> json.opt(key).takeUnless { it == org.json.JSONObject.NULL } }
            }
        }
        fun hide(context: Context, ids: List<String>) = change(context, ids, false)
        fun remove(context: Context, ids: List<String>) = change(context, ids, true)
        private fun change(context: Context, ids: List<String>, remove: Boolean) {
            require(ids.size <= 10000 && ids.all { it.isNotBlank() && it.length <= 128 })
            // Persist presentation dismissal without discarding restart/recovery metadata.
            for (name in listOf("future-notes-interrupted-jobs.json", "future-notes-jobs.json")) {
                val remaining = read(context, name).mapNotNull { record ->
                    if (record["id"] !in ids) record
                    else if (remove) null else record + ("notificationDismissed" to true)
                }
                val encoded = JSONArray(remaining).toString().toByteArray(Charsets.UTF_8)
                require(encoded.size <= 2 * 1024 * 1024)
                val record = file(context, name)
                val output = record.startWrite()
                try { output.write(encoded); record.finishWrite(output) }
                catch (error: Exception) { record.failWrite(output); throw error }
            }
        }
    }
}
