package com.nativedevps.futurenotes

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Separate authenticated private recovery format; library encryption is intact.
 * The OS-protected key and ciphertext are excluded from Android backup.
 */
class PrivateDrafts(private val context: Context, messenger: BinaryMessenger) {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "future_notes/private_drafts")
    private val aad = "future-notes-private-draft-v1".toByteArray(Charsets.UTF_8)
    init {
        channel.setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    val library = call.argument<String>("library") ?: throw IllegalArgumentException()
                    if (library.length !in 1..128) throw IllegalArgumentException()
                    val name = MessageDigest.getInstance("SHA-256").digest(library.toByteArray()).joinToString("") { "%02x".format(it) }
                    val file = AtomicFile(File(context.noBackupFilesDir, "draft-$name.bin"))
                    val value: Any? = when (call.method) {
                        "read" -> {
                            val bytes = try { file.openRead().use { if (it.channel.size() > LIMIT + 64) throw IllegalArgumentException(); it.readBytes() } } catch (_: java.io.FileNotFoundException) { null }
                            if (bytes == null) null else {
                                if (bytes.size < 30 || bytes[0].toInt() != 1 || bytes[1].toInt() != 12) throw IllegalArgumentException()
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(2, 14)))
                                cipher.updateAAD(aad)
                                cipher.doFinal(bytes.copyOfRange(14, bytes.size)).toString(Charsets.UTF_8)
                            }
                        }
                        "write" -> {
                            val json = call.argument<String>("json") ?: throw IllegalArgumentException()
                            val plain = json.toByteArray(Charsets.UTF_8)
                            if (plain.size > LIMIT) throw IllegalArgumentException()
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key())
                            cipher.updateAAD(aad)
                            val encrypted = cipher.doFinal(plain)
                            val output = file.startWrite()
                            try {
                                output.write(byteArrayOf(1, cipher.iv.size.toByte()))
                                output.write(cipher.iv); output.write(encrypted)
                                file.finishWrite(output)
                            } catch (error: Exception) { file.failWrite(output); throw error }
                            null
                        }
                        "discard" -> { file.delete(); null }
                        else -> throw IllegalArgumentException()
                    }
                    main.post { result.success(value) }
                } catch (_: Exception) {
                    main.post { result.error("draft_recovery_failed", "Private draft recovery could not be accessed. Existing recovery material was retained.", null) }
                }
            }
        }
    }
    @Synchronized
    private fun key(): SecretKey {
        val alias = context.packageName + ".private-drafts.v1"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    companion object { private const val LIMIT = 32 * 1024 * 1024 }
}
