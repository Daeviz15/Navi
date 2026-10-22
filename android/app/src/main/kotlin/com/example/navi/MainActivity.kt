package com.example.navi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var voiceOutput: NaviVoiceOutput? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceOutput = NaviVoiceOutput(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        voiceOutput?.close()
        voiceOutput = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
