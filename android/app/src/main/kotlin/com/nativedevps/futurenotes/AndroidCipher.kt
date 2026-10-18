package com.nativedevps.futurenotes

import android.content.Context
import android.app.ActivityManager
import android.os.PowerManager
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import java.util.zip.CRC32
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.math.min

/** Android provider implementation of the EXISTING SIC/PKCS7 layout. No new
 * algorithm, key derivation, envelope, library writer or persistence owner. */
class AndroidCipher(private val context: Context, messenger: BinaryMessenger,
                    private val acquireDocumentSource: (String) -> FileInputStream,
                    private val acquireDocumentOutput: (String, String) -> FileOutputStream) {
    private val channel = MethodChannel(messenger, "future_notes/cipher")
    private val main = Handler(Looper.getMainLooper())
    private val pool = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, LinkedBlockingQueue<Runnable>(64)).apply { allowCoreThreadTimeOut(true) }
    private val codecPool = ThreadPoolExecutor(1, 1, 30, TimeUnit.SECONDS, LinkedBlockingQueue<Runnable>(64)).apply { allowCoreThreadTimeOut(true) }
    private val active = ConcurrentHashMap.newKeySet<Work>()
    private val sequence = AtomicLong()
    @Volatile private var target = .7
    @Volatile private var parallel = 1
    @Volatile private var memoryMiB = 0
    @Volatile private var pressureUntil = 0L
    @Volatile private var pressure = 0
    private data class Budget(val duty: Double, val slots: Int)
    @Volatile private var budget = Budget(.7, 1)
    @Volatile private var sampledAt = 0L
    private val roots = listOfNotNull(File(context.applicationInfo.dataDir), context.getExternalFilesDir(null), context.externalCacheDir).map { it.canonicalFile }
    private val jobs = ConcurrentHashMap<String, Work>()
    private class Session(val cipher: Cipher?, val owner: String?, val digest: MessageDigest? = null, val crc: CRC32? = null)
    private val sessions = ConcurrentHashMap<String, Session>()
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "capabilities" -> { cipher(ByteArray(32), ByteArray(16)); available = true; result.success(mapOf("version" to 1, "native" to true, "streamChecksums" to true)) }
                    "configure" -> {
                        val percent = call.argument<Int>("target") ?: 70
                        require(percent in 10..90)
                        val count = (call.argument<Int>("parallel") ?: 0).coerceIn(0, 4).let { if (it == 0) 1 else it }
                        val memory = call.argument<Int>("memory") ?: 0
                        require(memory == 0 || memory in 64..65536)
                        target = percent / 100.0; parallel = count; memoryMiB = memory; sampledAt = 0
                        if (count > pool.maximumPoolSize) { pool.maximumPoolSize = count; pool.corePoolSize = count }
                        else { pool.corePoolSize = count; pool.maximumPoolSize = count }
                        result.success(null)
                    }
                    "start" -> {
                        require(jobs.size < 32)
                        val args = call.arguments as Map<*, *>
                        val id = UUID.randomUUID().toString()
                        val owner = args["owner"] as String?
                        require(owner == null || owner.length <= 64)
                        val work = Work((args["duty"] as? Number)?.toDouble() ?: 1.0, owner, sequence.incrementAndGet(), this::effectiveDuty)
                        jobs[id] = work
                        val task = Runnable { runTransform(work, args) }
                        work.task = task
                        try { pool.execute(task) }
                        catch (error: Exception) { jobs.remove(id); throw error }
                        result.success(id)
                    }
                    "poll" -> {
                        val id = call.argument<String>("id") ?: error("id")
                        val work = jobs[id] ?: error("missing")
                        work.heartbeat = SystemClock.elapsedRealtime()
                        work.duty = (call.argument<Number>("duty")?.toDouble() ?: work.duty).coerceIn(0.0, 1.0)
                        if (call.argument<Boolean>("cancel") == true) cancel(work)
                        val snapshot = work.snapshot()
                        if (snapshot["done"] == true) jobs.remove(id, work)
                        result.success(snapshot)
                    }
                    "releaseOwner" -> {
                        val owner = call.argument<String>("owner") ?: error("owner")
                        val owned = jobs.entries.filter { it.value.owner == owner }
                        owned.forEach { cancel(it.value) }
                        sessions.entries.removeAll { it.value.owner == owner }
                        fun acknowledge() {
                            if (owned.any { !it.value.finished }) main.postDelayed({ acknowledge() }, 20)
                            else { owned.forEach { jobs.remove(it.key, it.value) }; result.success(null) }
                        }
                        acknowledge()
                    }
                    "sessionOpen" -> {
                        require(sessions.size < 64)
                        val key = call.argument<ByteArray>("key") ?: error("key")
                        val instance = try { cipher(key, call.argument<ByteArray>("iv") ?: error("iv")) } finally { key.fill(0) }
                        val id = UUID.randomUUID().toString()
                        sessions[id] = Session(instance, call.argument<String>("owner"))
                        result.success(id)
                    }
                    "digestOpen" -> {
                        require(sessions.size < 64)
                        val owner = call.argument<String>("owner") ?: error("owner")
                        require(owner.isNotEmpty() && owner.length <= 64)
                        val id = UUID.randomUUID().toString()
                        sessions[id] = Session(null, owner, MessageDigest.getInstance("SHA-256"), CRC32())
                        result.success(id)
                    }
                    "sessionBudget" -> {
                        require(sessions.containsKey(call.argument<String>("id")))
                        result.success(sessionDuty())
                    }
                    "buffer", "sessionProcess", "sessionProcessMeasured", "sessionClose", "digestProcess", "digestResetCrc", "digestFinish" -> {
                        val args = call.arguments as Map<*, *>
                        codecPool.execute {
                            try {
                                val value: Any? = when (call.method) {
                                    "buffer" -> {
                                        val data = args["data"] as ByteArray
                                        require(data.size <= 32 * 1024 * 1024)
                                        val key = args["key"] as ByteArray
                                        try { buffer(data, key, args["iv"] as ByteArray, args["encrypt"] == true, args["padding"] != false) }
                                        finally { key.fill(0) }
                                    }
                                    "sessionProcess", "sessionProcessMeasured" -> {
                                        val instance = sessions[args["id"]]?.cipher ?: error("missing")
                                        val data = args["data"] as ByteArray
                                        require(data.size <= WINDOW)
                                        val started = Debug.threadCpuTimeNanos()
                                        val transformed = synchronized(instance) { instance.update(data).also { require(it.size == data.size) } }
                                        if (call.method == "sessionProcessMeasured") mapOf("data" to transformed,
                                            "cpuMicros" to ((Debug.threadCpuTimeNanos() - started).coerceAtLeast(0) / 1000), "duty" to sessionDuty())
                                        else transformed
                                    }
                                    "digestProcess" -> {
                                        val session = sessions[args["id"]] ?: error("missing")
                                        val data = args["data"] as ByteArray
                                        require(data.size <= WINDOW && session.digest != null && session.crc != null)
                                        val started = Debug.threadCpuTimeNanos()
                                        synchronized(session) {
                                            session.digest.update(data)
                                            if (args["crc"] == true) session.crc.update(data)
                                        }
                                        mapOf("crc" to session.crc.value,
                                            "cpuMicros" to ((Debug.threadCpuTimeNanos() - started).coerceAtLeast(0) / 1000), "duty" to sessionDuty())
                                    }
                                    "digestResetCrc" -> {
                                        val session = sessions[args["id"]] ?: error("missing")
                                        synchronized(session) { (session.crc ?: error("missing")).reset() }
                                        null
                                    }
                                    "digestFinish" -> {
                                        val session = sessions.remove(args["id"]) ?: error("missing")
                                        synchronized(session) { (session.digest ?: error("missing")).digest().hex() }
                                    }
                                    else -> { sessions.remove(args["id"]); null }
                                }
                                main.post { result.success(value) }
                            } catch (_: Exception) { main.post { result.error("cipher_input", "Native cipher input is invalid.", null) } }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("cipher_unavailable", "Native cipher operation could not start.", null) }
        }
    }

    fun memoryPressure(level: Int) {
        val tier = when (level) { 15, 80 -> 2; 5, 10, 40, 60 -> 1; else -> 0 }
        if (tier > 0) {
            val now = SystemClock.elapsedRealtime()
            pressure = if (now < pressureUntil) maxOf(pressure, tier) else tier
            pressureUntil = now + 15_000
            sampledAt = 0
        }
    }

    @Synchronized private fun sampleBudget(): Budget {
        val now = SystemClock.elapsedRealtime()
        if (now - sampledAt < 1000) return budget
        sampledAt = now
        val manager = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo(); manager.getMemoryInfo(memory)
        val runtime = Runtime.getRuntime()
        val available = minOf((memory.availMem-memory.threshold).coerceAtLeast(0),
            (runtime.maxMemory()-(runtime.totalMemory()-runtime.freeMemory())-16L*1024*1024).coerceAtLeast(0),
            manager.memoryClass.toLong()*1024*1024/2)
        var working = (available*target).toLong()
        if (memoryMiB > 0) working = minOf(working, memoryMiB.toLong()*1024*1024)
        val thermal = if (android.os.Build.VERSION.SDK_INT >= 29) context.getSystemService(PowerManager::class.java).currentThermalStatus else 0
        val factor = if (thermal >= 5) 0.0 else if (thermal >= 4) .2 else if (thermal >= 3) .5 else 1.0
        val memoryFactor = if (memory.lowMemory || (now < pressureUntil && pressure >= 2)) 0.0 else if (now < pressureUntil && pressure == 1) .5 else 1.0
        budget = Budget(target*minOf(factor,memoryFactor), minOf(parallel, runtime.availableProcessors().coerceAtLeast(1), (working/(16*1024*1024)).toInt()))
        return budget
    }

    private fun sessionDuty(): Double {
        val current = sampleBudget()
        return if (current.slots <= 0) 0.0 else minOf(current.duty, current.duty * current.slots / (active.size + 1).coerceAtLeast(1))
    }

    private fun effectiveDuty(work: Work): Double {
        val current = sampleBudget()
        val admitted = active.filter { !it.finished }.sortedBy { it.ordinal }.take(current.slots)
        return if (work in admitted) minOf(work.duty, current.duty) else 0.0
    }

    private fun cancel(work: Work) {
        synchronized(work) {
            work.cancelled = true
            if (!work.started) {
                work.task?.let { pool.remove(it) }
                work.task = null
                work.result = mapOf("error" to "cancelled")
                work.finished = true // No native handle was ever acquired.
            }
        }
    }

    private fun owned(path: String): File {
        require(File(path).isAbsolute)
        val file = File(path).canonicalFile
        // Canonical, separator-bounded containment also works on API 24/25;
        // java.nio.file.Path is only available from API 26.
        require(roots.any { file.path.startsWith(it.path + File.separator) && file != it })
        return file
    }

    private fun runTransform(work: Work, args: Map<*, *>) {
        synchronized(work) {
            if (work.finished) return
            work.started = true
            work.task = null
        }
        active.add(work)
        var output: File? = null
        var created = false
        var sourceKey: ByteArray? = null
        var destinationKey: ByteArray? = null
        var stage = 0
        val startedAt = SystemClock.elapsedRealtime()
        try {
            val sourcePath = args["source"] as String
            val documentSource = Regex("^/proc/self/fd/[0-9]+$").matches(sourcePath)
            val source = if (documentSource) File(sourcePath) else owned(sourcePath)
            val outputLease = args["outputSink"] as? String
            val destinationPath = args["destination"] as String
            val destinationFile = if (outputLease == null) owned(destinationPath) else File(destinationPath)
            output = destinationFile
            require(source != destinationFile && source.isFile)
            val offset = (args["offset"] as Number).toLong()
            val length = (args["length"] as Number).toLong()
            val decrypt = args["decrypt"] == true
            val encrypt = args["encrypt"] == true
            val verify = args["verify"] != false
            val maxPlain = (args["maxPlain"] as Number).toLong()
            val expected = (args["expected"] as? Number)?.toLong()
            require(offset >= 0 && length >= 0 && offset <= source.length() - length && maxPlain >= 0)
            require(!decrypt || (length >= 32 && (length - 16) % 16 == 0L))
            require(verify || (decrypt && !encrypt) ||
                (args["writeLease"] is String && work.owner != null))
            require(args["whole"] != true || (offset == 0L && length == source.length()))
            val sourceBytes = derive(args["sourcePassword"] as String?)
            val destinationBytes = derive(args["destinationPassword"] as String?)
            sourceKey = sourceBytes
            destinationKey = destinationBytes
            val sourceHash = (args["sourceHash"] as String?)?.let { MessageDigest.getInstance("SHA-256") }
            val plainHash = MessageDigest.getInstance("SHA-256")
            val outputHash = if (encrypt) MessageDigest.getInstance("SHA-256") else null
            var plainBytes = 0L
            var written = 0L
            stage = 1
            val inputStream = if (documentSource) acquireDocumentSource(sourcePath)
                else FileInputStream(Os.open(source.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0))
            inputStream.use { input ->
                val before = Os.fstat(input.fd)
                require(offset <= before.st_size - length)
                var sourcePosition = offset
                fun readSource(count: Int): ByteArray {
                    val bytes = read(input, count, sourcePosition)
                    sourcePosition += count
                    return bytes
                }
                work.check()
                stage = 2
                val outputStream = if (outputLease != null) acquireDocumentOutput(destinationPath, outputLease)
                    else FileOutputStream(Os.open(destinationFile.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384))
                created = outputLease == null
                outputStream.use { sink ->
                    val decoder = if (decrypt) cipher(sourceBytes, readSource(16).also { sourceHash?.update(it) }) else null
                    val encoder = if (encrypt) {
                        val iv = ByteArray(16).also { SecureRandom().nextBytes(it) }
                        sink.write(iv); outputHash?.update(iv); written += 16
                        cipher(destinationBytes, iv)
                    } else null
                    fun emit(bytes: ByteArray) {
                        plainBytes += bytes.size
                        require(plainBytes <= maxPlain)
                        plainHash.update(bytes)
                        val encoded = encoder?.update(bytes) ?: bytes
                        sink.write(encoded); outputHash?.update(encoded); written += encoded.size
                    }
                    var remaining = length - if (decrypt) 16 else 0
                    work.phase = if (decrypt) "Decrypting" else "Encrypting"
                    work.total = length
                    work.bytes = if (decrypt) 16 else 0
                    // Retain the last cipher block for strict PKCS7 validation.
                    val body = remaining - if (decrypt) 16 else 0
                    var bodyRemaining = body
                    stage = 3
                    while (bodyRemaining > 0) {
                        work.cooperate()
                        val bytes = readSource(min(WINDOW.toLong(), bodyRemaining).toInt())
                        val cpu = Debug.threadCpuTimeNanos()
                        sourceHash?.update(bytes)
                        emit(decoder?.update(bytes) ?: bytes)
                        work.compute += Debug.threadCpuTimeNanos() - cpu
                        bodyRemaining -= bytes.size; remaining -= bytes.size
                        work.bytes = length - remaining
                    }
                    if (decrypt) {
                        stage = 4
                        work.cooperate()
                        val tail = readSource(16)
                        val cpu = Debug.threadCpuTimeNanos()
                        sourceHash?.update(tail)
                        emit(unpad(decoder!!.update(tail)))
                        decoder.doFinal()
                        work.compute += Debug.threadCpuTimeNanos() - cpu
                    }
                    if (encoder != null) {
                        val padding = 16 - (plainBytes % 16).toInt()
                        val tail = encoder.update(ByteArray(padding) { padding.toByte() })
                        sink.write(tail); outputHash?.update(tail); written += tail.size
                        val end = encoder.doFinal()
                        sink.write(end); outputHash?.update(end); written += end.size
                    }
                    stage = 5
                    require(expected == null || expected == plainBytes)
                    val digest = plainHash.digest().hex()
                    require(sourceHash == null || sourceHash.digest().hex() == args["sourceHash"])
                    sink.fd.sync()
                    val after = Os.fstat(input.fd)
                    val current = Os.stat(source.path)
                    require(before.st_dev == current.st_dev && before.st_ino == current.st_ino && before.st_size == after.st_size && before.st_mtime == after.st_mtime && before.st_ctime == after.st_ctime)
                    work.check()
                    work.bytes = length
                    if (verify) {
                        stage = 6
                        work.phase = "Verifying"; work.bytes = 0
                        require(hashOutput(destinationFile, written, encrypt, destinationBytes, work,
                            if (outputLease != null) sink.fd else null) == digest)
                    }
                    work.check()
                    // Completion is published only after use{} closes all handles.
                    require(Os.fstat(sink.fd).st_size == written)
                    work.result = mapOf("length" to written, "hash" to digest,
                        "outputHash" to (outputHash?.digest()?.hex() ?: digest))
                }
            }
            MobileDiagnostics.record(MobileDiagnostics.Event.CIPHER_IO,
                "elapsed_ms" to (SystemClock.elapsedRealtime() - startedAt),
                "read_bytes" to (args["length"] as Number), "write_bytes" to (work.result["length"] as Number),
                "readback_bytes" to (if (args["verify"] != false) work.result["length"] as Number else 0),
                "encrypt" to (if (args["encrypt"] == true) 1 else 0), "decrypt" to (if (args["decrypt"] == true) 1 else 0))
            work.finished = true
        } catch (error: Exception) {
            if (created) output?.delete()
            MobileDiagnostics.record(MobileDiagnostics.Event.CIPHER_FAILED,
                "stage" to stage, "kind" to when (error) { is Cancelled -> 0; is IllegalArgumentException -> 1; else -> 2 })
            work.result = mapOf("error" to when (error) { is Cancelled -> "cancelled"; is IllegalArgumentException -> "input"; else -> "io" })
            work.finished = true
        } finally { sourceKey?.fill(0); destinationKey?.fill(0); active.remove(work) }
    }

    private fun hashOutput(file: File, length: Long, encrypted: Boolean, key: ByteArray, work: Work,
                           granted: java.io.FileDescriptor? = null): String {
        val hash = MessageDigest.getInstance("SHA-256")
        (if (granted == null) FileInputStream(file) else FileInputStream(Os.dup(granted))).use { input ->
            input.channel.position(0)
            val decoder = if (encrypted) cipher(key, read(input, 16)) else null
            var remaining = length - if (encrypted) 32 else 0
            while (remaining > 0) {
                work.cooperate()
                val bytes = read(input, min(WINDOW.toLong(), remaining).toInt())
                val cpu = Debug.threadCpuTimeNanos()
                hash.update(decoder?.update(bytes) ?: bytes)
                work.compute += Debug.threadCpuTimeNanos() - cpu
                remaining -= bytes.size
                work.bytes = min(work.total, length - remaining)
            }
            if (decoder != null) { work.check(); hash.update(unpad(decoder.update(read(input, 16)))); decoder.doFinal() }
        }
        work.bytes = work.total
        return hash.digest().hex()
    }

    private class Cancelled : Exception()
    private class Work(@Volatile var duty: Double, val owner: String?, val ordinal: Long, private val quota: (Work) -> Double) {
        var started = false // Guarded by this Work's monitor.
        var task: Runnable? = null
        @Volatile var cancelled = false
        @Volatile var heartbeat = SystemClock.elapsedRealtime()
        @Volatile var phase = "Queued"
        @Volatile var bytes = 0L
        @Volatile var total = 0L
        @Volatile var finished = false
        @Volatile var result: Map<String, Any> = emptyMap()
        var compute = 0L
        fun check() { if (cancelled || SystemClock.elapsedRealtime() - heartbeat > 30_000) throw Cancelled() }
        fun cooperate() {
            val worked = compute; compute = 0
            val started = System.nanoTime()
            while (true) {
                check()
                val fraction = quota(this).coerceIn(0.0, 1.0)
                val debt = if (fraction <= 0) 50_000_000.0 else worked * (1 - fraction) / fraction - (System.nanoTime() - started)
                if (fraction > 0 && debt <= 0) return
                Thread.sleep((debt / 1_000_000).toLong().coerceIn(1, 50))
            }
        }
        fun snapshot(): Map<String, Any> = if (finished) result + ("done" to true) else mapOf("done" to false, "phase" to phase, "bytes" to bytes, "total" to total)
    }

    companion object {
        @Volatile var available = false
            private set
        const val WINDOW = 1024 * 1024
        fun derive(password: String?): ByteArray = if (password == null) "MySuperSecretAppKeyForJsonStore!".toByteArray(Charsets.UTF_8) else password.toByteArray(Charsets.UTF_8).copyOf(32)
        fun cipher(key: ByteArray, iv: ByteArray): Cipher {
            require(iv.size == 16 && key.size in listOf(16,24,32))
            return Cipher.getInstance("AES/CTR/NoPadding").apply { init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv)) }
        }
        fun unpad(bytes: ByteArray): ByteArray {
            require(bytes.isNotEmpty())
            val padding = bytes.last().toInt() and 255
            require(padding in 1..16 && padding <= bytes.size)
            var mismatch = 0
            for (i in bytes.size-padding until bytes.size) mismatch = mismatch or ((bytes[i].toInt() and 255) xor padding)
            require(mismatch == 0)
            return bytes.copyOf(bytes.size-padding)
        }
        fun buffer(data: ByteArray, key: ByteArray, iv: ByteArray, encrypt: Boolean, padding: Boolean): ByteArray {
            val input = if (padding && encrypt) data + ByteArray(16-data.size%16) { (16-data.size%16).toByte() } else data
            if (padding && !encrypt) require(input.isNotEmpty() && input.size%16 == 0)
            val bytes = cipher(key, iv).doFinal(input)
            return if (padding && !encrypt) unpad(bytes) else bytes
        }
        fun read(input: FileInputStream, length: Int, position: Long? = null): ByteArray {
            val bytes = ByteArray(length)
            var offset = 0
            while (offset < length) {
                val count = if (position == null) input.read(bytes, offset, length-offset)
                    else input.channel.read(java.nio.ByteBuffer.wrap(bytes, offset, length-offset), position + offset)
                require(count > 0); offset += count
            }
            return bytes
        }
        fun ByteArray.hex(): String = joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
