package com.nativedevps.futurenotes

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/** Bounded JPEGs from a retained picked grant or an owned cache for explicit refresh.
 * No thumbnail files, library writes, playback or extra decryption pass. */
class AttachmentThumbnails(context: Context, messenger: BinaryMessenger,
    private val acquireSource: (String) -> FileInputStream) {
    private val root = File(context.cacheDir, "attachment-previews")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    init {
        MethodChannel(messenger, "future_notes/thumbnails").setMethodCallHandler { call, result ->
            if (call.method !in setOf("video", "picked", "cached", "generate")) { result.notImplemented(); return@setMethodCallHandler }
            val source = if (call.method == "generate") call.argument<String>("source") else call.method
            if (source !in setOf("video", "picked", "cached")) { result.error("thumbnail_input", "Thumbnail source unavailable.", null); return@setMethodCallHandler }
            val path = call.argument<String>("path")
            if (path == null) { result.error("thumbnail_input", "Thumbnail source unavailable.", null); return@setMethodCallHandler }
            worker.execute {
                var stage = 0
                var videoSourceGranted = false
                val bytes = try {
                    val input = if (source == "picked") acquireSource(path) else cached(path)
                    input.use {
                        stage = 1
                        val position = android.system.Os.lseek(it.fd, 0, android.system.OsConstants.SEEK_CUR)
                        try {
                            android.system.Os.lseek(it.fd, 0, android.system.OsConstants.SEEK_SET)
                            stage = 2
                            if (call.argument<String>("kind") == "image") image(it) else {
                                videoSourceGranted = true
                                frame(it)
                            }
                        } finally { android.system.Os.lseek(it.fd, position, android.system.OsConstants.SEEK_SET) }
                    }
                } catch (_: Exception) {
                    MobileDiagnostics.record(MobileDiagnostics.Event.THUMBNAIL_FAILED, "stage" to stage, "kind" to 1)
                    null
                } catch (_: OutOfMemoryError) {
                    MobileDiagnostics.record(MobileDiagnostics.Event.THUMBNAIL_FAILED, "stage" to stage, "kind" to 2)
                    null
                }
                main.post {
                    if (call.method == "generate") result.success(mapOf(
                        "jpeg" to bytes,
                        "fallback" to (bytes == null && videoSourceGranted)))
                    else result.success(bytes)
                }
            }
        }
    }
    private fun cached(path: String): FileInputStream {
        val file = File(path)
        require(file.isAbsolute && file.path == file.canonicalPath && file.isFile)
        require(file.canonicalPath.startsWith(root.canonicalPath + File.separator))
        return FileInputStream(file)
    }
    private fun encode(original: Bitmap): ByteArray? {
        val edge = max(original.width, original.height)
        val scaled = if (edge <= 160) original else Bitmap.createScaledBitmap(original,
            max(1, (original.width * 160.0 / edge).roundToInt()),
            max(1, (original.height * 160.0 / edge).roundToInt()), true)
        try {
            return ByteArrayOutputStream().use { output ->
                if (!scaled.compress(Bitmap.CompressFormat.JPEG, 75, output)) null
                else output.toByteArray().takeIf { it.size <= 32 * 1024 }
            }
        } finally {
            if (scaled !== original) scaled.recycle()
        }
    }
    private fun image(input: FileInputStream): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFileDescriptor(input.fd, null, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply {
            inSampleSize = 1
            while (max(bounds.outWidth, bounds.outHeight) / inSampleSize > 320) inSampleSize *= 2
        }
        android.system.Os.lseek(input.fd, 0, android.system.OsConstants.SEEK_SET)
        val bitmap = BitmapFactory.decodeFileDescriptor(input.fd, null, options) ?: return null
        try { return encode(bitmap) } finally { bitmap.recycle() }
    }
    private fun frame(input: FileInputStream): ByteArray? {
        val started = android.os.SystemClock.elapsedRealtime()
        val retriever = MediaMetadataRetriever()
        var bitmap: Bitmap? = null
        var stage = 10
        try {
            run {
                retriever.setDataSource(input.fd)
                stage = 11
                val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                val timeUs = if (duration != null && duration > 0) minOf(3_000_000L, (duration - 1).coerceAtLeast(0) * 1000) else 3_000_000L
                bitmap = if (Build.VERSION.SDK_INT >= 27) {
                    retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST, 160, 160)
                } else {
                    val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toLongOrNull() ?: return null
                    val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toLongOrNull() ?: return null
                    if (width <= 0 || height <= 0 || width * height > 16_777_216) return null
                    retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                }
                stage = 12
                val original = bitmap ?: run {
                    MobileDiagnostics.record(MobileDiagnostics.Event.THUMBNAIL_FAILED, "stage" to stage, "kind" to 0)
                    return null
                }
                val edge = max(original.width, original.height)
                if (edge > 160) {
                    bitmap = Bitmap.createScaledBitmap(original,
                        max(1, (original.width * 160.0 / edge).roundToInt()),
                        max(1, (original.height * 160.0 / edge).roundToInt()), true)
                    if (bitmap !== original) original.recycle()
                }
                stage = 13
                return ByteArrayOutputStream().use { output ->
                    if (!bitmap!!.compress(Bitmap.CompressFormat.JPEG, 75, output)) null else {
                        MobileDiagnostics.record(MobileDiagnostics.Event.THUMBNAIL_READY,
                            "time_us" to timeUs, "width" to bitmap!!.width, "height" to bitmap!!.height,
                            "bytes" to output.size(),
                            "elapsed_ms" to (android.os.SystemClock.elapsedRealtime() - started))
                        output.toByteArray()
                    }
                }
            }
        } catch (error: Exception) {
            MobileDiagnostics.record(MobileDiagnostics.Event.THUMBNAIL_FAILED, "stage" to stage, "kind" to 1)
            throw error
        } finally {
            bitmap?.recycle()
            retriever.release()
        }
    }
}
