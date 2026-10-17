package com.nativedevps.futurenotes

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.Context
import android.webkit.MimeTypeMap
import android.util.AtomicFile
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AttachmentFiles(private val context: Context, messenger: BinaryMessenger) {
    private var activity: Activity? = null
    private val channel = MethodChannel(messenger, "future_notes/files")
    private val root = File(context.cacheDir, "attachment-previews")
    fun attach(host: Activity) { activity = host }
    fun detach(host: Activity) { if (activity === host) activity = null }
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "readLibrarySelection" -> {
                        val file = AtomicFile(File(context.noBackupFilesDir, "future-notes-library.json"))
                        val bytes = try { file.openRead().use { if (it.channel.size() > 65536) throw IllegalStateException(); it.readBytes() } } catch (_: java.io.FileNotFoundException) { null }
                        if (bytes != null && bytes.size > 65536) throw IllegalStateException()
                        result.success(bytes?.toString(Charsets.UTF_8))
                    }
                    "writeLibrarySelection" -> {
                        val json = call.argument<String>("json") ?: throw IllegalStateException()
                        val bytes = json.toByteArray(Charsets.UTF_8)
                        if (bytes.size > 65536) throw IllegalStateException()
                        org.json.JSONObject(json)
                        val file = AtomicFile(File(context.noBackupFilesDir, "future-notes-library.json"))
                        val output = file.startWrite()
                        try { output.write(bytes); file.finishWrite(output) } catch (error: Exception) { file.failWrite(output); throw error }
                        result.success(null)
                    }
                    "cacheRoot" -> {
                        if (!root.isDirectory && !root.mkdirs()) throw IllegalStateException()
                        result.success(root.canonicalPath)
                    }
                    "privateAvailableBytes" -> result.success(android.os.StatFs(context.noBackupFilesDir.path).availableBytes)
                    "privateRoot" -> {
                        val privateRoot = File(context.noBackupFilesDir, "future-notes")
                        if (!privateRoot.isDirectory && !privateRoot.mkdirs()) throw IllegalStateException()
                        result.success(privateRoot.canonicalPath)
                    }
                    "openFile" -> {
                        val file = owned(call.argument<String>("path") ?: "")
                        if (!file.isFile) throw IllegalStateException()
                        val host = activity ?: throw IllegalStateException()
                        val uri = FileProvider.getUriForFile(context, context.packageName + ".attachments", file)
                        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mime)
                            clipData = ClipData.newRawUri("Attachment", uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        host.startActivity(intent)
                        result.success(null)
                    }
                    "revokeFiles" -> {
                        for (path in call.argument<List<String>>("paths") ?: emptyList()) {
                            val uri = FileProvider.getUriForFile(context, context.packageName + ".attachments", owned(path))
                            context.revokeUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("file_action_failed", "The attachment action could not be completed.", null)
            }
        }
    }
    private fun owned(path: String): File {
        val file = File(path)
        if (!file.isAbsolute || !file.canonicalPath.startsWith(root.canonicalPath + File.separator)) throw SecurityException()
        return file
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
