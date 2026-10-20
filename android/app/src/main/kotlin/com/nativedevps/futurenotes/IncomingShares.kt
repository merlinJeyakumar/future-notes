package com.nativedevps.futurenotes

import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Application-owned grants; the editor never owns an incoming Intent. */
class IncomingShares(messenger: BinaryMessenger, private val documents: LocalDocuments) {
    private val channel = MethodChannel(messenger, "future_notes/incoming_shares")
    private val pending = linkedMapOf<String, Map<String, Any?>>()
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pending" -> result.success(pending.values.toList())
                "claim" -> {
                    val id = call.argument<String>("id")
                    val lease = call.argument<String>("lease")
                    val batch = pending[id]
                    @Suppress("UNCHECKED_CAST")
                    val sources = batch?.get("sources") as? List<Map<String, Any?>> ?: emptyList()
                    val selected = sources.singleOrNull { it["lease"] == lease }
                    if (id == null || selected == null) {
                        result.error("share_unavailable", "This shared file is no longer available.", null)
                    } else {
                        val remaining = sources.filter { it["lease"] != lease }
                        if (remaining.isEmpty()) pending.remove(id)
                        else pending[id] = mapOf("id" to id, "sources" to remaining)
                        // The selected source transfers to the existing import owner.
                        result.success(selected)
                    }
                }
                "acknowledge", "discard" -> {
                    val batch = pending.remove(call.argument<String>("id"))
                    if (call.method == "discard" && batch != null) {
                        @Suppress("UNCHECKED_CAST")
                        documents.closeShared(batch["sources"] as? List<Map<String, Any?>> ?: emptyList())
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    @Suppress("DEPRECATION")
    fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND && intent?.action != Intent.ACTION_SEND_MULTIPLE) return
        val captured = intent ?: return
        val uris = linkedSetOf<Uri>()
        try {
            if (captured.action == Intent.ACTION_SEND_MULTIPLE) {
                captured.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            } else captured.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
            captured.clipData?.let { clip ->
                for (i in 0 until clip.itemCount.coerceAtMost(129)) clip.getItemAt(i).uri?.let { uris.add(it) }
            }
        } catch (_: RuntimeException) { uris.clear() }
        val flags = captured.flags
        // Clear only consumed share data. Activity recreation must not replay it.
        captured.action = null
        captured.removeExtra(Intent.EXTRA_STREAM)
        captured.clipData = null
        val id = UUID.randomUUID().toString()
        if (uris.isEmpty() || uris.size > 128 || uris.any { it.scheme != "content" }) {
            pending[id] = mapOf("id" to id, "sources" to emptyList<Any>(), "error" to "Share one or more readable files. Text-only and link-only shares are not attachments.")
            channel.invokeMethod("changed", null)
            return
        }
        documents.openShared(uris.toList(), flags) { sources, error ->
            pending[id] = mapOf("id" to id, "sources" to (sources ?: emptyList()), "error" to error)
            channel.invokeMethod("changed", null)
        }
    }
}
