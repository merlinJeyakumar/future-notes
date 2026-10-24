package com.nativedevps.futurenotes

import android.app.Application
import android.content.ComponentCallbacks2
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/** Exactly one runtime per process. Activity recreation reattaches to it;
 * it never starts a second Dart storage owner or reopens a live cache lease.
 */
class FutureNotesApplication : Application() {
    private var retained: FlutterEngine? = null
    lateinit var documents: LocalDocuments
        private set
    lateinit var files: AttachmentFiles
        private set
    lateinit var jobHost: AndroidJobHost
        private set
    lateinit var libraryEvents: LibraryEvents
        private set
    lateinit var attachmentDrop: AttachmentDrop
        private set
    lateinit var incomingShares: IncomingShares
        private set
    private var privateDrafts: PrivateDrafts? = null
    private var cipher: AndroidCipher? = null
    fun jobHostOrNull(): AndroidJobHost? = if (::jobHost.isInitialized) jobHost else null

    @Synchronized
    fun runtime(): FlutterEngine {
        retained?.let { MobileDiagnostics.record(MobileDiagnostics.Event.ENGINE_REUSED); return it }
        val engine = FlutterEngine(this)
        MobileDiagnostics.bind(engine.dartExecutor.binaryMessenger)
        documents = LocalDocuments(this, engine.dartExecutor.binaryMessenger)
        cipher = AndroidCipher(this, engine.dartExecutor.binaryMessenger, documents::acquireCipherSource, documents::acquireCipherOutput)
        libraryEvents = LibraryEvents(this, engine.dartExecutor.binaryMessenger)
        attachmentDrop = AttachmentDrop(engine.dartExecutor.binaryMessenger, documents)
        incomingShares = IncomingShares(engine.dartExecutor.binaryMessenger, documents)
        files = AttachmentFiles(this, engine.dartExecutor.binaryMessenger)
        AttachmentThumbnails(this, engine.dartExecutor.binaryMessenger, documents::acquireCipherSource)
        jobHost = AndroidJobHost(this, engine.dartExecutor.binaryMessenger)
        privateDrafts = PrivateDrafts(this, engine.dartExecutor.binaryMessenger)
        retained = engine
        MobileDiagnostics.record(MobileDiagnostics.Event.ENGINE_CREATED)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        return engine
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        jobHostOrNull()?.memoryPressure(level)
        cipher?.memoryPressure(level)
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW && level != ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN) {
            retained?.systemChannel?.sendMemoryPressureWarning()
        }
    }

    @Suppress("DEPRECATION")
    override fun onLowMemory() {
        super.onLowMemory()
        jobHostOrNull()?.memoryPressure(ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
        cipher?.memoryPressure(ComponentCallbacks2.TRIM_MEMORY_COMPLETE)
        retained?.systemChannel?.sendMemoryPressureWarning()
    }
}
