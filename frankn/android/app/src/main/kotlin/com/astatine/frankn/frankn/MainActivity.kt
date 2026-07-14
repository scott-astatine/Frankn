package com.astatine.frankn.frankn

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "frankn/sharing"
    private var sharedData: List<Map<String, String>>? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getSharedData") {
                result.success(sharedData)
                sharedData = null // Reset after consumption
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type

        val dataList = mutableListOf<Map<String, String>>()

        if (Intent.ACTION_SEND == action && type != null) {
            if ("text/plain" == type) {
                intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                    dataList.add(mapOf("type" to "text", "value" to text))
                }
            } else {
                @Suppress("DEPRECATION")
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uri ->
                    val path = cacheUriToFile(uri)
                    if (path != null) {
                        dataList.add(mapOf("type" to "file", "value" to path))
                    }
                }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && type != null) {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris ->
                for (uri in uris) {
                    val path = cacheUriToFile(uri)
                    if (path != null) {
                        dataList.add(mapOf("type" to "file", "value" to path))
                    }
                }
            }
        }

        if (dataList.isNotEmpty()) {
            sharedData = dataList
            // If the Flutter channel is active, immediately push the update to Dart
            methodChannel?.invokeMethod("onSharedDataReceived", sharedData)
        }
    }

    // Helper to query the actual display name of the URI
    private fun getFileName(uri: Uri): String {
        var name = ""
        try {
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex != -1) {
                        name = it.getString(nameIndex)
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        if (name.isEmpty()) {
            name = uri.lastPathSegment?.substringAfterLast('/') ?: "shared_file_${System.currentTimeMillis()}"
        }
        return name
    }

    // Helper to copy a system content:// URI into a readable cache file
    private fun cacheUriToFile(uri: Uri): String? {
        return try {
            val fileName = getFileName(uri)
            val cacheFile = File(cacheDir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            cacheFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}