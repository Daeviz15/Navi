package com.example.navi

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * In-memory neural PCM16 WAV playback (`AudioTrack`) + Google Neural/Network TTS fallback.
 * Utterance IDs survive every native callback.
 */
class NaviVoiceOutput(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, AudioManager.OnAudioFocusChangeListener {
    private val context = context.applicationContext
    private val channel = MethodChannel(messenger, "navi/voice_output")
    private val main = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var engine: TextToSpeech? = null
    private var track: AudioTrack? = null
    private var completionRunnable: Runnable? = null
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
            "playFillerWav" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (ready && activeId == null && bytes != null && bytes.size > 44 && requestFocus()) {
                    playFillerBytes(bytes)
                }
                result.success(null)
            }
            "playWav" -> {
                val id = call.argument<String>("id")
                val bytes = call.argument<ByteArray>("bytes")
                val fallbackText = call.argument<String>("text")
                if (!ready || id.isNullOrBlank() || bytes == null || bytes.size <= 44) {
                    result.error("voice_unavailable", "WAV payload invalid.", null)
                } else if (!requestFocus()) {
                    result.error("audio_focus", "Audio is busy.", null)
                } else {
                    playWavBytes(id, bytes, fallbackText, result)
                }
            }
            "speak" -> {
                val id = call.argument<String>("id")
                val text = call.argument<String>("text")
                if (!ready || id.isNullOrBlank() || text.isNullOrBlank() || text.length > 500) {
                    result.error("voice_unavailable", "Voice is not ready.", null)
                } else if (!requestFocus()) {
                    result.error("audio_focus", "Audio is busy.", null)
                } else {
                    releasePlayer()
                    activeId = id
                    val params = Bundle().apply {
                        putString(TextToSpeech.Engine.KEY_FEATURE_NETWORK_SYNTHESIS, "true")
                    }
                    val accepted = engine!!.speak(text, TextToSpeech.QUEUE_FLUSH, params, id)
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

    private fun playWavBytes(
        id: String,
        bytes: ByteArray,
        fallbackText: String?,
        result: MethodChannel.Result
    ) {
        try {
            releasePlayer()
            engine?.stop()
            val sampleRate = ByteBuffer.wrap(bytes, 24, 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .int
                .coerceIn(8000, 48000)
            val pcmLength = (bytes.size - 44) and -2
            if (pcmLength <= 0) throw IllegalArgumentException("Empty PCM payload")

            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val audioTrack = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(pcmLength)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            val written = audioTrack.write(bytes, 44, pcmLength)
            if (written <= 0) {
                audioTrack.release()
                throw IllegalStateException("AudioTrack write failed: $written")
            }

            activeId = id
            track = audioTrack
            audioTrack.play()
            emit("started", id)

            val durationMs = ((pcmLength.toLong() * 1000L) / (sampleRate.toLong() * 2L)) + 60L
            val doneTask = Runnable {
                if (activeId == id) {
                    releasePlayer()
                    emit("completed", id)
                }
            }
            completionRunnable = doneTask
            main.postDelayed(doneTask, durationMs)
            result.success(null)
        } catch (_: Exception) {
            releasePlayer()
            if (!fallbackText.isNullOrBlank() && engine != null) {
                activeId = id
                val accepted = engine!!.speak(fallbackText, TextToSpeech.QUEUE_FLUSH, Bundle(), id)
                if (accepted != TextToSpeech.ERROR) {
                    result.success(null)
                    return
                }
            }
            activeId = null
            abandonFocus()
            result.error("voice_output", "WAV playback could not start.", null)
        }
    }

    private fun playFillerBytes(bytes: ByteArray) {
        try {
            releasePlayer()
            val sampleRate = ByteBuffer.wrap(bytes, 24, 4)
                .order(ByteOrder.LITTLE_ENDIAN)
                .int
                .coerceIn(8000, 48000)
            val pcmLength = (bytes.size - 44) and -2
            if (pcmLength <= 0) return

            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()
            val audioTrack = AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(pcmLength)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            if (audioTrack.write(bytes, 44, pcmLength) > 0) {
                track = audioTrack
                audioTrack.play()
            } else {
                audioTrack.release()
            }
        } catch (_: Exception) {
            releasePlayer()
        }
    }

    private fun releasePlayer() {
        completionRunnable?.let { main.removeCallbacks(it) }
        completionRunnable = null
        val current = track
        track = null
        if (current != null) {
            try {
                if (current.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    current.stop()
                }
            } catch (_: Exception) {}
            try {
                current.release()
            } catch (_: Exception) {}
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        if (ready) { result.success(null); return }
        if (initializing != null) {
            result.error("voice_busy", "Voice is already initializing.", null); return
        }
        initializing = result
        val token = ++generation
        // Prefer Google Speech Services ("com.google.android.tts") for natural neural voices.
        engine = TextToSpeech(context, { status -> main.post {
            if (generation != token) return@post
            val pending = initializing ?: return@post
            initializing = null
            val tts = engine
            if (status != TextToSpeech.SUCCESS || tts == null) {
                pending.error("voice_output", "Speech engine unavailable.", null)
                return@post
            }
            val voices = tts.voices.orEmpty().filter {
                it.locale.language == "en" &&
                    !it.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
            }
            // Prefer high-quality neural/network voices and natural regional accents (NG, GB, US)
            // instead of forcing the phone's low-footprint offline robotic synthesizer.
            val voice = voices.sortedWith(
                compareByDescending<android.speech.tts.Voice> {
                    it.isNetworkConnectionRequired ||
                        it.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NETWORK_SYNTHESIS) ||
                        it.name.lowercase().let { n -> n.contains("wavenet") || n.contains("neural") || n.contains("network") }
                }
                .thenByDescending { it.quality }
                .thenByDescending {
                    when (it.locale.country.uppercase()) {
                        "US" -> 3
                        "GB" -> 2
                        "NG" -> 1
                        else -> 0
                    }
                }
                .thenBy { it.latency }
            ).firstOrNull()
            if (voice != null) {
                tts.setVoice(voice)
            }
            tts.setSpeechRate(1.0f)
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
        } }, "com.google.android.tts")
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
        releasePlayer()
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
            activeId = null
            releasePlayer()
            engine?.stop()
            abandonFocus()
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
