package com.nativedevps.futurenotes

import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Provider notifications and resume invalidate metadata only. No path guessing. */
class LibraryEvents(context: Context, messenger: BinaryMessenger) {
    private val resolver = context.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "future_notes/library_events")
    private val observers = mutableMapOf<String, ContentObserver>()
    private val cursors = mutableMapOf<String, Cursor>()
    private val requested = mutableSetOf<String>()
    private val pending = mutableMapOf<String, Runnable>()
    init {
        channel.setMethodCallHandler { call, result ->
            val token = call.argument<String>("library")
            try {
                require(token != null)
                when (call.method) {
                    "watch" -> if (!observers.containsKey(token)) {
                        val tree = Uri.parse(token)
                        require(tree.authority == "com.android.externalstorage.documents" && DocumentsContract.isTreeUri(tree))
                        require(resolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission && it.isWritePermission })
                        val observer = object : ContentObserver(main) {
                            override fun onChange(selfChange: Boolean, uri: Uri?) { changed(token) }
                        }
                        requested.add(token)
                        val directory = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                        // The returned cursor transports provider-authorized change
                        // notifications, even when its notification URI has no /tree
                        // prefix. Never request a broader provider permission.
                        val cursor = resolver.query(directory, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                            ?: throw IllegalStateException()
                        cursor.registerContentObserver(observer)
                        cursors[token] = cursor
                        observers[token] = observer
                    }
                    "unwatch" -> {
                        requested.remove(token)
                        val cursor = cursors.remove(token)
                        observers.remove(token)?.let { cursor?.unregisterContentObserver(it) }
                        cursor?.close()
                        pending.remove(token)?.let { main.removeCallbacks(it) }
                    }
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (_: Exception) { result.error("watch_unavailable", "Folder change notifications are unavailable. Refresh or reopen the app to rescan.", null) }
        }
    }
    private fun changed(token: String) {
        if (!requested.contains(token) || pending.containsKey(token)) return
        val task = Runnable { pending.remove(token); if (requested.contains(token)) channel.invokeMethod("changed", token) }
        pending[token] = task
        main.postDelayed(task, 1500)
    }
    fun resumed() { requested.toList().forEach(::changed) }
}
