package com.nativedevps.futurenotes

import android.app.Activity
import android.content.Intent
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.UUID
import java.io.FileInputStream
import java.io.FileOutputStream
import android.system.Os
import android.system.OsConstants

/** SAF identities stay opaque. Only the system local/SD provider is admitted.
 * Operations run serially off the UI thread; publication belongs to Dart's
 * recovery coordinator, not to this primitive adapter.
 */
class LocalDocuments(context: Context, messenger: BinaryMessenger) {
    private var activity: Activity? = null
    private val resolver = context.applicationContext.contentResolver
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "future_notes/documents")
    private var picker: MethodChannel.Result? = null
    private val sources = mutableMapOf<String, Pair<String, ParcelFileDescriptor>>()
    // A staged transfer keeps its granted handle until flush instead of
    // reopening the provider for every 1 MiB message. All access is serialized.
    private val appenders = linkedMapOf<String, FileOutputStream>()
    private data class OutputLease(val library: String, val uri: Uri, val fd: ParcelFileDescriptor, var claimed: Boolean = false)
    private val outputs = mutableMapOf<String, OutputLease>()
    fun acquireCipherOutput(path: String, lease: String): FileOutputStream = executor.submit<FileOutputStream> {
        val output = outputs[lease] ?: throw DocumentFailure("invalid_handle", "Output lease expired.")
        require(path == "/proc/self/fd/${output.fd.fd}" && output.fd.statSize == 0L && !output.claimed)
        output.claimed = true
        // Preserve the SAF grant. Reopening /proc/self/fd performs a new
        // scoped-storage permission check; dup retains the granted handle.
        FileOutputStream(Os.dup(output.fd.fileDescriptor))
    }.get()

    private val pickedUris = mutableMapOf<String, Uri>()
    private val dropGrants = mutableMapOf<String, android.view.DragAndDropPermissions>()
    private val forgetUris = mutableSetOf<Uri>()
    fun attach(host: Activity) { activity = host }
    fun detach(host: Activity) { if (activity === host) activity = null }

    /** Duplicate a granted read handle. Cipher reads are positional, so each
     * job has an independent logical cursor despite the duplicated descriptor.
     * Never canonicalize provider descriptors into guessed filesystem paths.
     * Acquisition and release run on the same executor, preventing fd reuse
     * between checking the registry and opening the independent handle. */
    fun acquireCipherSource(path: String): FileInputStream = executor.submit<FileInputStream> {
        require(sources.values.any { path == "/proc/self/fd/${it.second.fd}" })
        val source = sources.values.single { path == "/proc/self/fd/${it.second.fd}" }.second
        FileInputStream(Os.dup(source.fileDescriptor))
    }.get()

    init { channel.setMethodCallHandler(::handle) }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "pickFile") {
            val host = activity
            if (host == null || picker != null) { result.error("picker_busy", "Open the app and finish its current picker first.", null); return }
            picker = result
            host.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            }, REQUEST_FILE)
            return
        }
        if (call.method == "selectLocalFolder") {
            val host = activity
            if (host == null) { result.error("activity_unavailable", "Open the app before selecting a folder.", null); return }
            if (picker != null) {
                result.error("picker_busy", "A folder picker is already open.", null)
                return
            }
            picker = result
            host.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }, REQUEST_FOLDER)
            return
        }
        executor.execute {
            try {
                val value = execute(call)
                main.post { result.success(value) }
            } catch (error: DocumentFailure) {
                main.post { result.error(error.code, error.message, null) }
            } catch (_: SecurityException) {
                main.post { result.error("permission_revoked", "Folder access was revoked. Select the folder again.", null) }
            } catch (_: Exception) {
                main.post { result.error("document_io", "The selected folder is unavailable or could not complete this operation.", null) }
            }
        }
    }

    fun activityResult(request: Int, status: Int, data: Intent?): Boolean {
        if (request != REQUEST_FOLDER && request != REQUEST_FILE) return false
        val result = picker ?: return true
        picker = null
        if (status != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }
        if (request == REQUEST_FILE) {
            val uri = data.data!!
            executor.execute {
                var descriptor: ParcelFileDescriptor? = null
                try {
                    if (uri.scheme != "content") throw DocumentFailure("unsupported_document", "Select a native document.")
                    if (data.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0) {
                        resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (!it.moveToFirst()) throw DocumentFailure("missing_document", "The selected file is unavailable.")
                        it.getString(0)
                    } ?: throw DocumentFailure("missing_document", "The selected file is unavailable.")
                    descriptor = resolver.openFileDescriptor(uri, "r") ?: throw DocumentFailure("read_failed", "The selected file could not be opened.")
                    val length = descriptor.statSize
                    if (length < 0) throw DocumentFailure("unsupported_document", "This provider does not expose a seekable file. Choose an on-device or SD-card file.")
                    val lease = UUID.randomUUID().toString()
                    val source = mapOf("lease" to lease, "path" to "/proc/self/fd/${descriptor.fd}", "length" to length, "identity" to uri.toString(), "name" to name)
                    sources[lease] = Pair("picked", descriptor)
                    pickedUris[lease] = uri
                    descriptor = null
                    main.post { result.success(source) }
                } catch (_: Exception) {
                    descriptor?.close()
                    main.post { result.error("pick_failed", "The selected file could not be opened as a seekable native source.", null) }
                }
            }
            return true
        }
        try {
            val tree = data.data!!
            requireLocal(tree)
            val required = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            if (data.flags and required != required) throw DocumentFailure("missing_grant", "Read and write folder access is required.")
            resolver.takePersistableUriPermission(tree, required)
            result.success(tree.toString())
        } catch (error: DocumentFailure) {
            result.error(error.code, error.message, null)
        } catch (_: Exception) {
            result.error("missing_grant", "Persistent folder access could not be retained.", null)
        }
        return true
    }

    fun openDropped(uris: List<Uri>, grant: android.view.DragAndDropPermissions, callback: (List<Map<String, Any?>>?, String?) -> Unit) {
        executor.execute {
            val opened = mutableListOf<Map<String, Any?>>()
            try {
                for (uri in uris) {
                    val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (!it.moveToFirst()) throw IllegalStateException(); it.getString(0)
                    } ?: throw IllegalStateException()
                    val fd = resolver.openFileDescriptor(uri, "r") ?: throw IllegalStateException()
                    if (fd.statSize < 0) { fd.close(); throw IllegalStateException() }
                    val lease = UUID.randomUUID().toString()
                    sources[lease] = Pair("picked", fd); pickedUris[lease] = uri; dropGrants[lease] = grant
                    opened.add(mapOf("lease" to lease, "path" to "/proc/self/fd/${fd.fd}", "length" to fd.statSize, "identity" to uri.toString(), "name" to name))
                }
                main.post { callback(opened, null) }
            } catch (_: Exception) {
                for (source in opened) { val key = source["lease"] as String; sources.remove(key)?.second?.close(); pickedUris.remove(key); dropGrants.remove(key) }
                grant.release()
                main.post { callback(null, "Dropped files could not be opened. Choose native on-device files.") }
            }
        }
    }

    private fun requireLocal(tree: Uri) {
        if (tree.scheme != "content" || tree.authority != "com.android.externalstorage.documents" ||
            !DocumentsContract.isTreeUri(tree)) {
            throw DocumentFailure("unsupported_provider", "Select an on-device or SD-card folder. Cloud providers are not supported.")
        }
    }

    private fun tree(call: MethodCall): Uri {
        val tree = Uri.parse(call.argument<String>("library") ?: throw DocumentFailure("invalid_handle", "Missing folder handle."))
        requireLocal(tree)
        if (resolver.persistedUriPermissions.none { it.uri == tree && it.isReadPermission && it.isWritePermission }) {
            throw DocumentFailure("permission_revoked", "Persistent read/write access is no longer available.")
        }
        return tree
    }

    private fun root(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

    private fun document(call: MethodCall, tree: Uri): Uri {
        val uri = Uri.parse(call.argument<String>("document") ?: throw DocumentFailure("invalid_handle", "Missing document handle."))
        if (uri.scheme != "content" || uri.authority != tree.authority ||
            !DocumentsContract.isTreeUri(uri) ||
            DocumentsContract.getTreeDocumentId(uri) != DocumentsContract.getTreeDocumentId(tree) ||
            (uri != root(tree) && !isScopedChild(tree, uri))) {
            throw DocumentFailure("outside_library", "The document is outside the selected folder.")
        }
        return uri
    }

    private fun isScopedChild(tree: Uri, uri: Uri): Boolean {
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            return DocumentsContract.isChildDocument(resolver, root(tree), uri)
        }
        // API 24-28 has no public isChildDocument client API. A tree-scoped
        // document query invokes DocumentsProvider.enforceTree on the provider
        // before returning metadata. Keep the exact authority/tree/grant checks
        // above; never interpret an opaque document ID as a filesystem path.
        return try {
            resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use {
                it.count == 1 && it.moveToFirst() && it.getString(0) == DocumentsContract.getDocumentId(uri)
            } ?: false
        } catch (_: SecurityException) { false }
    }

    private fun metadata(uri: Uri): Map<String, Any?> {
        resolver.query(uri, COLUMNS, null, null, null)?.use { cursor ->
            if (cursor.count != 1 || !cursor.moveToFirst()) throw DocumentFailure("missing_document", "The document is missing or ambiguous.")
            val flags = cursor.getLong(4)
            if (flags and DocumentsContract.Document.FLAG_VIRTUAL_DOCUMENT.toLong() != 0L ||
                flags and DocumentsContract.Document.FLAG_PARTIAL.toLong() != 0L) {
                throw DocumentFailure("unsupported_document", "Virtual or partial documents cannot be used in a live library.")
            }
            return mapOf(
                "token" to uri.toString(), "name" to cursor.getString(0),
                "directory" to (cursor.getString(1) == DocumentsContract.Document.MIME_TYPE_DIR),
                "length" to if (cursor.isNull(2)) null else cursor.getLong(2),
                "modified" to if (cursor.isNull(3)) null else cursor.getLong(3)
            )
        }
        throw DocumentFailure("missing_document", "The document is unavailable.")
    }

    private fun children(tree: Uri, parent: Uri): List<Map<String, Any?>> {
        val query = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(parent))
        val entries = mutableListOf<Map<String, Any?>>()
        resolver.query(query, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                if (entries.size >= 10000) throw DocumentFailure("inventory_limit", "This folder exceeds the supported inventory size.")
                val child = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                entries.add(metadata(child))
            }
        } ?: throw DocumentFailure("listing_failed", "The folder could not be listed.")
        return entries
    }

    private fun name(call: MethodCall): String {
        val value = call.argument<String>("name") ?: ""
        if (value.isEmpty() || value.length > 240 || value == "." || value == ".." ||
            value.any { it == '/' || it == '\\' || it.code < 32 }) {
            throw DocumentFailure("invalid_name", "Invalid document name.")
        }
        return value
    }

    private fun execute(call: MethodCall): Any? {
        if (call.method == "forgetPickedSource") {
            val uri = Uri.parse(call.argument<String>("identity") ?: throw DocumentFailure("invalid_handle", "Missing input identity."))
            forgetUris.add(uri); releasePickedGrant(uri); return null
        }
        if (call.method == "reopenPickedSource") {
            val uri = Uri.parse(call.argument<String>("identity") ?: throw DocumentFailure("invalid_handle", "Missing input identity."))
            if (uri.scheme != "content" || resolver.persistedUriPermissions.none { it.uri == uri && it.isReadPermission }) throw DocumentFailure("permission_revoked", "Select the original input again.")
            val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (!it.moveToFirst()) throw DocumentFailure("missing_document", "The input is unavailable."); it.getString(0) } ?: throw DocumentFailure("missing_document", "The input is unavailable.")
            val source = resolver.openFileDescriptor(uri, "r") ?: throw DocumentFailure("read_failed", "The input could not be opened.")
            val length = source.statSize
            if (length < 0) { source.close(); throw DocumentFailure("unsupported_document", "A seekable input is required.") }
            val lease = UUID.randomUUID().toString(); sources[lease] = Pair("picked", source); pickedUris[lease] = uri
            return mapOf("lease" to lease, "path" to "/proc/self/fd/${source.fd}", "length" to length, "identity" to uri.toString(), "name" to name)
        }
        if (call.method == "closePickedSource") {
            val key = call.argument<String>("lease") ?: throw DocumentFailure("invalid_handle", "Missing source lease.")
            val source = sources[key]
            if (source?.first == "picked") { sources.remove(key); source.second.close(); pickedUris.remove(key)?.let { releasePickedGrant(it) }; dropGrants.remove(key)?.let { grant -> if (dropGrants.values.none { it === grant }) grant.release() } }
            return null
        }
        if (call.method == "closeOutputSink") {
            val key = call.argument<String>("lease") ?: throw DocumentFailure("invalid_handle", "Missing output lease.")
            val output = outputs[key]
            if (output != null && output.library == call.argument<String>("library")) { outputs.remove(key); output.fd.close() }
            return null
        }
        if (call.method == "borrowReader" || call.method == "checkReader") {
            val path = call.argument<String>("path") ?: throw DocumentFailure("invalid_handle", "Missing read capability.")
            val entry = sources.entries.singleOrNull { path == "/proc/self/fd/${it.value.second.fd}" }
                ?: throw DocumentFailure("invalid_handle", "Read capability expired.")
            val status = Os.fstat(entry.value.second.fileDescriptor)
            require(OsConstants.S_ISREG(status.st_mode) && status.st_size >= 0)
            val stamp = "${status.st_dev}:${status.st_ino}:${status.st_size}:${status.st_mtime}:${status.st_ctime}"
            if (call.method == "checkReader") {
                require(call.argument<String>("lease") == entry.key && call.argument<String>("stamp") == stamp)
                return null
            }
            return mapOf("fd" to entry.value.second.fd, "length" to status.st_size, "lease" to entry.key, "stamp" to stamp)
        }
        val tree = tree(call)
        if (call.method == "closeSource") {
            val key = call.argument<String>("lease") ?: throw DocumentFailure("invalid_handle", "Missing source lease.")
            val source = sources[key]
            if (source != null && source.first == tree.toString()) {
                sources.remove(key)
                source.second.close()
            }
            return null
        }
        if (call.method == "checkOutputSink") {
            val key = call.argument<String>("lease") ?: throw DocumentFailure("invalid_handle", "Missing output lease.")
            val output = outputs[key] ?: throw DocumentFailure("invalid_handle", "Output lease expired.")
            require(output.library == tree.toString() && call.argument<String>("path") == "/proc/self/fd/${output.fd.fd}" && call.argument<String>("document") == output.uri.toString())
            val info = metadata(output.uri)
            require(info["length"] == output.fd.statSize)
            return info
        }
        if (call.method == "root") return metadata(root(tree))
        val doc = document(call, tree)
        when (call.method) {
            "availableBytes" -> {
                resolver.openFileDescriptor(doc, "r")?.use { descriptor ->
                    val space = android.system.Os.fstatvfs(descriptor.fileDescriptor)
                    return Math.multiplyExact(space.f_bavail, space.f_frsize)
                } ?: throw DocumentFailure("capacity_unavailable", "The selected filesystem capacity is unavailable.")
            }
            "openOutputSink" -> {
                val name = name(call)
                require(Regex("^\\.future-notes-owned-[a-f0-9-]{36}\\.pending$").matches(name))
                if (children(tree, doc).any { it["name"] == name }) throw DocumentFailure("name_exists", "Output already exists.")
                val created = DocumentsContract.createDocument(resolver, doc, "application/octet-stream", name)
                    ?: throw DocumentFailure("create_failed", "Output candidate could not be created.")
                val descriptor = resolver.openFileDescriptor(created, "rw") ?: throw DocumentFailure("write_failed", "Output could not be opened.")
                try {
                    val status = Os.fstat(descriptor.fileDescriptor)
                    require(OsConstants.S_ISREG(status.st_mode) && status.st_size == 0L)
                    val key = UUID.randomUUID().toString()
                    val info = metadata(created)
                    require(info["name"] == name && info["length"] == 0L)
                    outputs[key] = OutputLease(tree.toString(), created, descriptor)
                    return mapOf("lease" to key, "path" to "/proc/self/fd/${descriptor.fd}", "document" to info)
                } catch (error: Exception) { descriptor.close(); throw error }
            }
            "stat" -> return metadata(doc)
            "openSource" -> {
                val info = metadata(doc)
                if (info["directory"] == true) throw DocumentFailure("not_file", "Select a file.")
                val descriptor = resolver.openFileDescriptor(doc, "r") ?: throw DocumentFailure("read_failed", "The document could not be opened.")
                val key = UUID.randomUUID().toString()
                sources[key] = Pair(tree.toString(), descriptor)
                return mapOf("lease" to key, "path" to "/proc/self/fd/${descriptor.fd}", "length" to descriptor.statSize, "identity" to doc.toString())
            }
            "children" -> return children(tree, doc)
            "create" -> {
                val name = name(call)
                if (children(tree, doc).any { it["name"] == name }) throw DocumentFailure("name_exists", "A document with this name already exists.")
                val mime = if (call.argument<Boolean>("directory") == true) DocumentsContract.Document.MIME_TYPE_DIR else "application/octet-stream"
                val created = DocumentsContract.createDocument(resolver, doc, mime, name)
                    ?: throw DocumentFailure("create_failed", "The document could not be created.")
                val info = metadata(created)
                if (info["name"] != name) throw DocumentFailure("changed_name", "The provider changed the requested filename.")
                return info
            }
            "read" -> {
                val offset = call.argument<Number>("offset")?.toLong() ?: -1
                val length = call.argument<Number>("length")?.toInt() ?: 0
                range(offset, length)
                resolver.openFileDescriptor(doc, "r")?.let { descriptor ->
                    ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                        val buffer = ByteBuffer.allocate(length)
                        input.channel.position(offset)
                        while (buffer.hasRemaining()) { if (input.channel.read(buffer) <= 0) break }
                        return buffer.array().copyOf(buffer.position())
                    }
                }
                throw DocumentFailure("read_failed", "The document could not be read.")
            }
            "append" -> {
                val offset = call.argument<Number>("offset")?.toLong() ?: -1
                val bytes = call.argument<ByteArray>("bytes") ?: byteArrayOf()
                range(offset, bytes.size)
                val key = doc.toString()
                try {
                    val output = appenders[key] ?: run {
                        if (appenders.size >= 8) {
                            val oldest = appenders.keys.first()
                            appenders.remove(oldest)?.close()
                        }
                        val descriptor = resolver.openFileDescriptor(doc, "rw")
                            ?: throw DocumentFailure("write_failed", "The document could not be written.")
                        ParcelFileDescriptor.AutoCloseOutputStream(descriptor).also { appenders[key] = it }
                    }
                    if (output.channel.size() != offset) throw DocumentFailure("revision_changed", "The staged document length changed.")
                    output.channel.position(offset)
                    val buffer = ByteBuffer.wrap(bytes)
                    while (buffer.hasRemaining()) {
                        if (output.channel.write(buffer) <= 0) throw DocumentFailure("short_write", "The provider did not accept all bytes.")
                    }
                } catch (error: Exception) {
                    appenders.remove(key)?.close()
                    throw error
                }
            }
            "flush" -> {
                val output = appenders.remove(doc.toString())
                if (output != null) output.use { it.fd.sync() }
                else resolver.openFileDescriptor(doc, "rw")?.use { it.fileDescriptor.sync() }
                    ?: throw DocumentFailure("flush_failed", "The document could not be flushed.")
            }
            "rename" -> {
                appenders.remove(doc.toString())?.close()
                if (doc == root(tree)) throw DocumentFailure("root_rename", "The selected folder cannot be renamed.")
                val name = name(call)
                // The caller rechecks exact sibling inventory and content after
                // rename. No atomic/no-replace guarantee is inferred here.
                val renamed = DocumentsContract.renameDocument(resolver, doc, name)
                    ?: throw DocumentFailure("rename_failed", "The provider could not rename the document.")
                return metadata(renamed)
            }
            "delete" -> {
                appenders.remove(doc.toString())?.close()
                if (doc == root(tree)) throw DocumentFailure("root_delete", "The selected folder cannot be deleted.")
                if (metadata(doc)["directory"] == true && children(tree, doc).isNotEmpty()) {
                    throw DocumentFailure("not_empty", "Unrecognized folder contents were retained.")
                }
                if (!DocumentsContract.deleteDocument(resolver, doc)) throw DocumentFailure("delete_failed", "The document could not be removed.")
            }
            else -> throw DocumentFailure("unsupported_operation", "Unsupported document operation.")
        }
        return null
    }

    private fun releasePickedGrant(uri: Uri) {
        if (!forgetUris.contains(uri) || pickedUris.values.contains(uri) || DocumentsContract.isTreeUri(uri)) return
        try { resolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: SecurityException) { }
        forgetUris.remove(uri)
    }

    private fun range(offset: Long, length: Int) {
        if (offset < 0 || length !in 1..1048576) throw DocumentFailure("invalid_range", "Invalid byte range.")
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        picker?.error("picker_closed", "The activity closed before folder selection completed.", null)
        picker = null
        // Join already queued I/O before releasing descriptors used by it.
        executor.execute {
            appenders.values.forEach { it.close() }; appenders.clear()
            sources.values.forEach { it.second.close() }; sources.clear()
        }
        executor.shutdown()
    }

    private class DocumentFailure(val code: String, message: String): Exception(message)

    companion object {
        private const val REQUEST_FOLDER = 24081
        private const val REQUEST_FILE = 24084
        private val COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS
        )
    }
}
