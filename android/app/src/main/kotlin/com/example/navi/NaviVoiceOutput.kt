package com.example.navi

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Installed, offline English TTS. Utterance IDs survive every native callback. */
class NaviVoiceOutput(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, AudioManager.OnAudioFocusChangeListener {
    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, "navi/voice_output")
    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var engine: TextToSpeech? = null
    private var initializing: MethodChannel.Result? = null
    private var generation = 0
    private var ready = false
    private var activeId: String? = null
    private var focus: AudioFocusRequest? = null
    private val attributes = AudioAttributes.Builder()
        .setUsage(if (Build.VERSION.SDK_INT >= 26) AudioAttributes.USAGE_ASSISTANT
                  else AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "speak" -> {
                val id = call.argument<String>("id")
                val text = call.argument<String>("text")
                if (!ready || id.isNullOrBlank() || text.isNullOrBlank() || text.length > 500) {
                    result.error("voice_unavailable", "Voice is not ready.", null)
                } else if (!requestFocus()) {
                    result.error("audio_focus", "Audio is busy.", null)
                } else {
                    activeId = id
                    val accepted = engine!!.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), id)
                    if (accepted == TextToSpeech.ERROR) {
                        activeId = null
                        abandonFocus()
                        result.error("voice_output", "Speech could not start.", null)
                    } else result.success(null)
                }
            }
            "stop" -> { stop(); result.success(null) }
            "dispose" -> { disposeEngine(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        if (ready) { result.success(null); return }
        if (initializing != null) {
            result.error("voice_busy", "Voice is already initializing.", null); return
        }
        initializing = result
        val token = ++generation
        engine = TextToSpeech(context) { status -> main.post {
            if (generation != token) return@post
            val pending = initializing ?: return@post
            initializing = null
            val tts = engine
            if (status != TextToSpeech.SUCCESS || tts == null) {
                pending.error("voice_output", "Speech engine unavailable.", null)
                return@post
            }
            val voice = tts.voices.orEmpty().filter {
                it.locale.language == "en" && !it.isNetworkConnectionRequired &&
                    !it.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
            }.sortedWith(compareByDescending<android.speech.tts.Voice> {
                it.locale.country == "NG"
            }.thenByDescending { it.quality }.thenBy { it.latency }).firstOrNull()
            if (voice == null || tts.setVoice(voice) == TextToSpeech.ERROR) {
                pending.error("offline_voice_missing", "Install an offline English voice.", null)
                return@post
            }
            tts.setSpeechRate(0.95f)
            tts.setPitch(1.0f)
            tts.setAudioAttributes(attributes)
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String) = emit("started", id)
                override fun onDone(id: String) = emit("completed", id)
                @Deprecated("Use the error-code overload")
                override fun onError(id: String) = emit("failed", id)
                override fun onError(id: String, code: Int) = emit("failed", id)
                override fun onStop(id: String, interrupted: Boolean) = emit("cancelled", id)
            })
            ready = true
            pending.success(null)
        } }
    }

    private fun emit(event: String, id: String) { main.post {
        if (activeId != id) return@post
        channel.invokeMethod(event, mapOf("id" to id))
        if (event != "started") {
            activeId = null
            abandonFocus()
        }
    } }

    private fun stop() {
        val id = activeId
        activeId = null
        engine?.stop()
        abandonFocus()
        if (id != null) channel.invokeMethod("cancelled", mapOf("id" to id))
    }

    @Suppress("DEPRECATION")
    private fun requestFocus(): Boolean {
        val granted = if (Build.VERSION.SDK_INT >= 26) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes).setOnAudioFocusChangeListener(this).build()
            focus = request
            audio.requestAudioFocus(request)
        } else audio.requestAudioFocus(this, AudioManager.STREAM_MUSIC,
            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        return granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= 26) focus?.let { audio.abandonAudioFocusRequest(it) }
        else audio.abandonAudioFocus(this)
        focus = null
    }

    override fun onAudioFocusChange(change: Int) {
        if (change < 0) {
            val id = activeId
            stop()
            if (id != null) channel.invokeMethod("failed", mapOf("id" to id))
        }
    }

    private fun disposeEngine() {
        ++generation
        initializing?.error("voice_cancelled", "Voice initialization cancelled.", null)
        initializing = null
        stop()
        ready = false
        engine?.shutdown()
        engine = null
    }

    fun close() {
        disposeEngine()
        channel.setMethodCallHandler(null)
    }
}
