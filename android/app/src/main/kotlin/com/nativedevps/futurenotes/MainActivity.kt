package com.nativedevps.futurenotes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.content.res.Configuration
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private var documents: LocalDocuments? = null
    private var files: AttachmentFiles? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine = (application as FutureNotesApplication).runtime()
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        MobileDiagnostics.record(MobileDiagnostics.Event.ACTIVITY_CREATED, "restored" to if (savedInstanceState != null) 1 else 0)
        (application as FutureNotesApplication).jobHost.notificationIntent(intent)
        if (BuildConfig.FLAVOR == "preview") {
            // Explicitly allow developer screenshots/recording. Production keeps
            // its platform capture protection independently of build signing.
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        } else if (Build.VERSION.SDK_INT >= 33) {
            setRecentsScreenshotEnabled(false)
        } else {
            // Older Android has no recents-only screenshot protection API.
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        (application as FutureNotesApplication).jobHost.notificationIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val runtime = application as FutureNotesApplication
        documents = runtime.documents.also { it.attach(this) }
        files = runtime.files.also { it.attach(this) }
        runtime.jobHost.attach(this)
        runtime.attachmentDrop.attach(this)
    }

    override fun onResume() {
        super.onResume()
        MobileDiagnostics.record(MobileDiagnostics.Event.ACTIVITY_RESUMED)
        (application as FutureNotesApplication).libraryEvents.resumed()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        MobileDiagnostics.record(MobileDiagnostics.Event.CONFIGURATION,
            "orientation" to newConfig.orientation, "width_dp" to newConfig.screenWidthDp, "height_dp" to newConfig.screenHeightDp)
    }

    override fun onPause() {
        MobileDiagnostics.record(MobileDiagnostics.Event.ACTIVITY_PAUSED)
        super.onPause()
    }

    override fun onDestroy() {
        MobileDiagnostics.record(MobileDiagnostics.Event.ACTIVITY_DESTROYED,
            "configuration" to if (isChangingConfigurations) 1 else 0, "finishing" to if (isFinishing) 1 else 0)
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documents?.activityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (!(application as FutureNotesApplication).jobHost.permissionResult(requestCode, grantResults)) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        (application as FutureNotesApplication).attachmentDrop.detach(this)
        documents?.detach(this)
        documents = null
        files?.detach(this)
        files = null
        (application as FutureNotesApplication).jobHost.detach(this)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
