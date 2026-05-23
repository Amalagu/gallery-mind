package com.example.gallerymind

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// MainActivity is the Android side of GalleryMind. Flutter talks to this file
// through a MethodChannel whenever it needs permissions, ONNX inference,
// MediaStore indexing, gallery bytes, or Android sharing.
class MainActivity : FlutterActivity() {
    private val channelName = "gallerymind/clip"
    private val prefsName = "gallerymind_prefs"
    private val onboardingCompleteKey = "onboarding_complete"
    private val permissionRequestCode = 4401
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var clipBridge: ClipOnnxBridge
    private lateinit var methodChannel: MethodChannel
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        clipBridge = ClipOnnxBridge(applicationContext)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel.setMethodCallHandler { call, result ->
            try {
                // Each method name here matches a Dart call in EmbeddingIndex.
                // Heavy methods run on a background thread so the UI stays fluid.
                when (call.method) {
                    "initialize" -> runAsync(result) {
                        clipBridge.initialize()
                        true
                    }
                    "initializeTextSearch" -> runAsync(result) {
                        clipBridge.initializeTextSearch()
                        true
                    }
                    "embedText" -> runAsync(result) {
                        val text = call.argument<String>("text").orEmpty()
                        clipBridge.embedText(text).toDoubleArray()
                    }
                    "embedImageBytes" -> runAsync(result) {
                        val bytes = call.argument<ByteArray>("bytes")
                            ?: throw IllegalArgumentException("Missing image bytes")
                        clipBridge.embedImageBytes(bytes).toDoubleArray()
                    }
                    "embedImageAsset" -> runAsync(result) {
                        val assetPath = call.argument<String>("assetPath")
                            ?: throw IllegalArgumentException("Missing assetPath")
                        clipBridge.embedImageAsset(assetPath).toDoubleArray()
                    }
                    "indexImageAsset" -> runAsync(result) {
                        clipBridge.indexImageAsset(
                            id = call.argument<String>("id")
                                ?: throw IllegalArgumentException("Missing id"),
                            uri = call.argument<String>("uri")
                                ?: throw IllegalArgumentException("Missing uri"),
                            assetPath = call.argument<String>("assetPath")
                                ?: throw IllegalArgumentException("Missing assetPath"),
                            title = call.argument<String>("title").orEmpty(),
                            description = call.argument<String>("description").orEmpty(),
                            tags = call.argument<List<String>>("tags") ?: emptyList(),
                            dateTakenMillis = call.argument<Long>("dateTakenMillis")
                                ?: System.currentTimeMillis(),
                        )
                    }
                    "indexImageBytes" -> runAsync(result) {
                        clipBridge.indexImageBytes(
                            id = call.argument<String>("id")
                                ?: throw IllegalArgumentException("Missing id"),
                            uri = call.argument<String>("uri")
                                ?: throw IllegalArgumentException("Missing uri"),
                            bytes = call.argument<ByteArray>("bytes")
                                ?: throw IllegalArgumentException("Missing image bytes"),
                            title = call.argument<String>("title").orEmpty(),
                            description = call.argument<String>("description").orEmpty(),
                            tags = call.argument<List<String>>("tags") ?: emptyList(),
                            dateTakenMillis = call.argument<Long>("dateTakenMillis")
                                ?: System.currentTimeMillis(),
                        )
                    }
                    "indexNewGalleryImages" -> runAsync(result) {
                        // Progress events are pushed back to Dart while the
                        // long-running gallery indexing loop is still active.
                        clipBridge.indexNewGalleryImages(
                            includeAlreadyIndexed = call.argument<Boolean>("includeAlreadyIndexed")
                                ?: false,
                            limit = call.argument<Int>("limit"),
                        ) { progress ->
                            mainHandler.post {
                                methodChannel.invokeMethod("indexProgress", progress)
                            }
                        }
                    }
                    "searchText" -> runAsync(result) {
                        // Text search compares the query embedding against both
                        // image embeddings and optional caption/tag embeddings.
                        clipBridge.searchText(
                            query = call.argument<String>("query").orEmpty(),
                            limit = call.argument<Int>("limit") ?: 30,
                            imageWeight = call.argument<Double>("imageWeight") ?: 0.7,
                            captionWeight = call.argument<Double>("captionWeight") ?: 0.3,
                            threshold = call.argument<Double>("threshold") ?: 0.5,
                        )
                    }
                    "findSimilarImages" -> runAsync(result) {
                        // Detail-page suggestions compare image embedding to
                        // image embedding and use a stricter threshold.
                        clipBridge.findSimilarImages(
                            sourceImageId = call.argument<String>("sourceImageId")
                                ?: throw IllegalArgumentException("Missing sourceImageId"),
                            threshold = call.argument<Double>("threshold") ?: 0.8,
                            limit = call.argument<Int>("limit") ?: 60,
                        )
                    }
                    "getAllIndexedImages" -> runAsync(result) {
                        clipBridge.getAllIndexedImages(
                            limit = call.argument<Int>("limit") ?: 90,
                        )
                    }
                    "getImageBytes" -> runAsync(result) {
                        clipBridge.getImageBytes(
                            uri = call.argument<String>("uri")
                                ?: throw IllegalArgumentException("Missing uri"),
                            maxSize = call.argument<Int>("maxSize") ?: 640,
                        )
                    }
                    "shareImage" -> {
                        // Sharing launches an Android ACTION_SEND intent, so it
                        // must run on the activity thread rather than runAsync.
                        val uri = call.argument<String>("uri")
                            ?: throw IllegalArgumentException("Missing uri")
                        shareImage(uri, result)
                    }
                    "countIndexedImages" -> runAsync(result) { clipBridge.countIndexedImages() }
                    "clearIndex" -> runAsync(result) {
                        clipBridge.clearIndex()
                        true
                    }
                    "hasPhotoPermission" -> result.success(hasPhotoPermission())
                    "requestPhotoPermission" -> requestPhotoPermission(result)
                    "hasCompletedOnboarding" -> result.success(hasCompletedOnboarding())
                    "completeOnboarding" -> {
                        setOnboardingComplete()
                        result.success(true)
                    }
                    "close" -> runAsync(result) {
                        clipBridge.close()
                        true
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                Log.e(logTag, "MethodChannel error in ${call.method}: ${error.message}", error)
                result.error("CLIP_BRIDGE_ERROR", error.message, error.stackTraceToString())
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            // Complete the pending MethodChannel call that originally requested
            // the permission prompt.
            pendingPermissionResult?.success(
                grantResults.any { it == PackageManager.PERMISSION_GRANTED },
            )
            pendingPermissionResult = null
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any) {
        // MethodChannel callbacks must return on the main thread, but ONNX and
        // SQLite work should not block it.
        Thread {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                Log.e(logTag, "Async bridge error: ${error.message}", error)
                mainHandler.post {
                    result.error("CLIP_BRIDGE_ERROR", error.message, error.stackTraceToString())
                }
            }
        }.start()
    }

    private fun requestPhotoPermission(result: MethodChannel.Result) {
        // Android only allows one permission dialog flow at a time, so keep the
        // pending result and reject duplicate attempts until it completes.
        if (hasPhotoPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("PERMISSION_IN_PROGRESS", "Photo permission request already active", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            photoPermissionNames(),
            permissionRequestCode,
        )
    }

    private fun shareImage(uriString: String, result: MethodChannel.Result) {
        // Gallery images are content:// URIs. Granting read permission on the
        // intent lets the receiving app open the selected image.
        if (!uriString.startsWith("content://")) {
            result.error(
                "UNSHAREABLE_IMAGE",
                "Only device gallery images can be shared right now",
                null,
            )
            return
        }

        val uri = Uri.parse(uriString)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(intent, "Share image").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        applicationContext.startActivity(chooser)
        result.success(true)
    }

    private fun hasPhotoPermission(): Boolean {
        return photoPermissionNames().any { permission ->
            ContextCompat.checkSelfPermission(
                this,
                permission,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun photoPermissionNames(): Array<String> {
        // Android 13+ split media permissions by type; older versions use the
        // legacy external storage read permission. Android 14+ can also grant
        // selected-photo access, which still gives the app usable MediaStore
        // rows for the user's chosen images.
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                arrayOf(
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                )
            } else {
                arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
            }
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
    }

    private fun hasCompletedOnboarding(): Boolean {
        // SharedPreferences is enough for a simple "only show onboarding once"
        // flag because it survives app restarts.
        return getSharedPreferences(prefsName, MODE_PRIVATE)
            .getBoolean(onboardingCompleteKey, false)
    }

    private fun setOnboardingComplete() {
        getSharedPreferences(prefsName, MODE_PRIVATE)
            .edit()
            .putBoolean(onboardingCompleteKey, true)
            .apply()
    }
}

private fun FloatArray.toDoubleArray(): DoubleArray {
    // Flutter MethodChannel serializes DoubleArray more predictably than
    // FloatArray, so embeddings are converted before crossing into Dart.
    return DoubleArray(size) { index -> this[index].toDouble() }
}

private const val logTag = "GalleryMindMain"
