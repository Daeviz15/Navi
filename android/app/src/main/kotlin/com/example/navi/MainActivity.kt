package com.example.navi

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var voiceOutput: NaviVoiceOutput? = null
    private var mapsConfiguration: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceOutput = NaviVoiceOutput(this, flutterEngine.dartExecutor.binaryMessenger)
        mapsConfiguration = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "navi/maps_configuration"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isConfigured" -> {
                        @Suppress("DEPRECATION")
                        val metadata = packageManager.getApplicationInfo(
                            packageName, PackageManager.GET_META_DATA
                        ).metaData
                        // Only expose configuration presence to Dart, never the key.
                        result.success(!metadata?.getString("com.google.android.geo.API_KEY").isNullOrBlank())
                    }
                    "appIdentity" -> result.success(AndroidAppIdentity.getCredentials(this))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        voiceOutput?.close()
        voiceOutput = null
        mapsConfiguration?.setMethodCallHandler(null)
        mapsConfiguration = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
