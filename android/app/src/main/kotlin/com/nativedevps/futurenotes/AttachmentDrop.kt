package com.nativedevps.futurenotes

import android.app.Activity
import android.view.DragEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Grants live with the source descriptors, including after a preview closes. */
class AttachmentDrop(messenger: BinaryMessenger, private val documents: LocalDocuments) {
    private val channel = MethodChannel(messenger, "future_notes/drop")
    private var host: Activity? = null
    private var target: String? = null
    private var dragTarget: String? = null
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "target") { target = call.argument<String>("token"); result.success(null) }
            else result.notImplemented()
        }
    }
    fun attach(activity: Activity) {
        host = activity
        activity.window.decorView.setOnDragListener { _, event ->
            when (event.action) {
                DragEvent.ACTION_DRAG_STARTED -> {
                    dragTarget = target
                    val accepts = target != null && event.clipDescription != null
                    if (accepts) channel.invokeMethod("hover", true)
                    accepts
                }
                DragEvent.ACTION_DRAG_ENTERED -> { if (dragTarget != null) channel.invokeMethod("hover", true); true }
                DragEvent.ACTION_DRAG_EXITED, DragEvent.ACTION_DRAG_ENDED -> { channel.invokeMethod("hover", false); true }
                DragEvent.ACTION_DROP -> {
                    channel.invokeMethod("hover", false)
                    val captured = dragTarget
                    val clip = event.clipData
                    if (captured == null || captured != target || clip == null || clip.itemCount !in 1..128) false
                    else {
                        val uris = (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }.distinct()
                        if (uris.isEmpty() || uris.any { it.scheme != "content" }) false
                        else {
                            val grant = activity.requestDragAndDropPermissions(event)
                            if (grant == null) false
                            else { documents.openDropped(uris, grant) { sources, error ->
                                if (sources != null) channel.invokeMethod("files", mapOf("target" to captured, "sources" to sources))
                                else channel.invokeMethod("error", error)
                            }; true }
                        }
                    }
                }
                else -> true
            }
        }
    }
    fun detach(activity: Activity) {
        if (host === activity) { activity.window.decorView.setOnDragListener(null); host = null; dragTarget = null }
    }
}
