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
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import android.net.Uri
import android.provider.DocumentsContract

class AttachmentFiles(private val context: Context, messenger: BinaryMessenger) {
    private var activity: Activity? = null
    private val channel = MethodChannel(messenger, "future_notes/files")
    private val root = File(context.cacheDir, "attachment-previews")
    // User-owned export work must not be reclaimed with the OS cache. The exact
    // folder is excluded from backup and is the only new FileProvider scope.
    private val exportRoot = File(context.filesDir, "prepared-exports")
    private val exportExecutor = Executors.newSingleThreadExecutor()
    private val settingsExecutor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var exportPicker: Pair<File, MethodChannel.Result>? = null
    private val exportRequest = 6831
    fun attach(host: Activity) { activity = host }
    fun detach(host: Activity) { if (activity === host) activity = null }
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "readSettings", "writeSettings" -> {
                        settingsExecutor.execute {
                            try {
                                val file = AtomicFile(File(context.noBackupFilesDir, "future-notes-settings-v1.json"))
                                val value: String? = if (call.method == "readSettings") {
                                    try {
                                        file.openRead().use { input ->
                                            if (input.channel.size() > 65536) throw IllegalStateException()
                                            val bytes = input.readBytes()
                                            if (bytes.size > 65536) throw IllegalStateException()
                                            Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                                                .also { org.json.JSONObject(it) }
                                        }
                                    } catch (error: java.io.FileNotFoundException) {
                                        if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) throw error
                                        null
                                    }
                                } else {
                                    val json = call.argument<String>("json") ?: throw IllegalStateException()
                                    val bytes = json.toByteArray(Charsets.UTF_8)
                                    if (bytes.size > 65536) throw IllegalStateException()
                                    org.json.JSONObject(json)
                                    val output = file.startWrite()
                                    try {
                                        output.write(bytes); output.fd.sync(); file.finishWrite(output)
                                    } catch (error: Exception) { file.failWrite(output); throw error }
                                    // A bounded settings acknowledgement, never a payload scan.
                                    file.openRead().use { if (it.channel.size() > 65536 || !it.readBytes().contentEquals(bytes)) throw IllegalStateException() }
                                    null
                                }
                                main.post { result.success(value) }
                            } catch (_: Exception) {
                                main.post { result.error("settings_io_failed", "Settings could not be saved or restored.", null) }
                            }
                        }
                    }
                    "shareExport" -> {
                        val file = ownedExport(call.argument<String>("path") ?: "")
                        val host = activity ?: throw IllegalStateException()
                        val uri = FileProvider.getUriForFile(context, context.packageName + ".attachments", file)
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = if (file.extension == "zip") "application/zip" else "application/octet-stream"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            clipData = ClipData.newRawUri("Export", uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        host.startActivity(Intent.createChooser(intent, "Share export"))
                        result.success(true)
                    }
                    "saveExport" -> {
                        if (exportPicker != null) throw IllegalStateException()
                        val file = ownedExport(call.argument<String>("path") ?: "")
                        val host = activity ?: throw IllegalStateException()
                        exportPicker = Pair(file, result)
                        try {
                            host.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if (file.extension == "zip") "application/zip" else "application/octet-stream"
                                putExtra(Intent.EXTRA_TITLE, file.name)
                                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            }, exportRequest)
                        } catch (error: Exception) { exportPicker = null; throw error }
                    }
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
                    "exportRoot" -> {
                        if (!exportRoot.isDirectory && !exportRoot.mkdirs()) throw IllegalStateException()
                        result.success(exportRoot.canonicalPath)
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
    private fun ownedExport(path: String): File {
        val file = File(path)
        // Keep already-owned legacy handoffs valid, without admitting files
        // elsewhere in cacheDir/filesDir or widening the provider grant.
        val allowedRoots = listOf(exportRoot.canonicalFile, File(context.cacheDir, "prepared-exports").canonicalFile)
        require(file.isAbsolute && file.path == file.canonicalPath && file.isFile)
        require(file.parentFile?.parentFile in allowedRoots && file.parentFile!!.name.startsWith("future-notes-export-"))
        return file
    }
    fun activityResult(request: Int, status: Int, data: Intent?): Boolean {
        if (request != exportRequest) return false
        val pending = exportPicker ?: return true
        if (status != Activity.RESULT_OK || data?.data == null) {
            exportPicker = null; pending.second.success(false); return true
        }
        val uri = data.data!!
        exportExecutor.execute {
            try {
                require(uri.scheme == "content")
                val file = ownedExport(pending.first.path)
                val length = file.length(); val modified = file.lastModified()
                var bytes = 0L; var last = 0L
                fun progress() { val amount = bytes; main.post { channel.invokeMethod("exportSaveProgress", mapOf("bytes" to amount, "total" to length)) } }
                file.inputStream().use { input ->
                    val descriptor = context.contentResolver.openFileDescriptor(uri, "w") ?: throw IllegalStateException()
                    android.os.ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
                        val buffer = ByteArray(256 * 1024)
                        progress()
                        while (true) {
                            val count = input.read(buffer); if (count < 0) break
                            if (bytes + count > length) throw IllegalStateException()
                            output.write(buffer, 0, count); bytes += count
                            val now = android.os.SystemClock.elapsedRealtime()
                            if (now - last >= 150) { last = now; progress() }
                        }
                        require(bytes == length && file.length() == length && file.lastModified() == modified)
                        output.flush()
                    }
                }
                progress()
                main.post { exportPicker = null; pending.second.success(true) }
            } catch (_: Exception) {
                // ACTION_CREATE_DOCUMENT created this target for this request.
                // Retain the private prepared file so the user can retry.
                try { DocumentsContract.deleteDocument(context.contentResolver, uri) } catch (_: Exception) { }
                main.post { exportPicker = null; pending.second.error("export_save_failed", "The file could not be saved. The prepared export is still available.", null) }
            }
        }
        return true
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
