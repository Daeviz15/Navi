import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../domain/lagos_gazetteer.dart';
import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'cloud_http_client.dart';
import 'pcm_audio_levels.dart';
import 'wav_encoder.dart';

/// Push-to-talk / turn-based cloud speech engine backed by Groq Whisper
/// (`whisper-large-v3-turbo`).
///
/// Uses client-side RMS voice activity detection with a 300 ms pre-roll buffer
/// so silence is never uploaded and initial consonants are never clipped.
class GroqSpeechEngine implements SpeechEngine {
  GroqSpeechEngine({
    String? apiKey,
    Uri? endpoint,
    this.model = const String.fromEnvironment(
      'NAVI_GROQ_STT_MODEL',
      defaultValue: 'whisper-large-v3-turbo',
    ),
    this.prompt = LagosGazetteer.whisperPrompt,
    CloudHttpTransport? http,
    this.speechThresholdDbfs = -43.0,
    this.silenceThresholdDbfs = -45.0,
    this.silenceEndpointFrames =
        15, // 750 ms (15 * 50 ms frames) for natural pauses
    this.minSpeechFrames = 4, // 200 ms minimum voiced speech
    this.maxUtteranceBytes = 1024000, // 32 seconds at 16 kHz mono PCM16
    this.requestTimeout = const Duration(seconds: 10),
  }) : _apiKey = (apiKey ?? const String.fromEnvironment('GROQ_API_KEY'))
           .trim(),
       _endpoint =
           endpoint ??
           Uri.parse(
             const String.fromEnvironment(
               'NAVI_STT_URL',
               defaultValue:
                   'https://api.groq.com/openai/v1/audio/transcriptions',
             ),
           ),
       _http = http ?? DartIoCloudHttpTransport(),
       _ownsHttp = http == null;

  static const _preRollBytes = 9600; // 300 ms at 16 kHz mono PCM16 (32 KB/s).
  static const _frameSamples = 800; // 50 ms window at 16 kHz.
  static const _diagnostics = bool.fromEnvironment('NAVI_VOICE_DIAGNOSTICS');

  String _apiKey;
  final Uri _endpoint;
  final String model;
  final String prompt;
  final CloudHttpTransport _http;
  final bool _ownsHttp;
  final double speechThresholdDbfs;
  final double silenceThresholdDbfs;
  final int silenceEndpointFrames;
  final int minSpeechFrames;
  final int maxUtteranceBytes;
  final Duration requestTimeout;

  final _events = StreamController<SpeechEvent>.broadcast();
  final _meter = PcmAudioMeter(windowSamples: _frameSamples);
  final _preRoll = Queue<Uint8List>();
  final _speechBuffer = BytesBuilder(copy: false);

  SpeechMode _mode = SpeechMode.muted;
  int _epoch = 0;
  int _preRollLength = 0;
  int _voicedFrames = 0;
  int _silentFramesAfterSpeech = 0;
  double _peakSpeechDbfs = -100.0;
  bool _speechDetected = false;
  bool _transcribing = false;
  bool _initialized = false;
  bool _disposed = false;

  bool get isConfigured =>
      _apiKey.isNotEmpty || _endpoint.host != 'api.groq.com';

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_disposed) throw const VoiceException(VoiceFailure.interrupted);
    if (_apiKey.isEmpty && _http is DartIoCloudHttpTransport) {
      _apiKey = await CloudEnvConfig.resolveKey('GROQ_API_KEY', _apiKey);
    }
    if (!isConfigured) {
      throw const VoiceException(VoiceFailure.unavailable);
    }
    _initialized = true;
  }

  @override
  void setMode(SpeechMode mode) {
    if (_disposed) return;
    _epoch++;
    _mode = mode;
    _resetCaptureBuffer();
    if (_initialized && mode == SpeechMode.wake) {
      // In wake mode, promote immediately so push-to-talk turns start listening
      // without requiring a separate offline keyword model.
      final activeEpoch = _epoch;
      scheduleMicrotask(() {
        if (!_disposed && _epoch == activeEpoch && _mode == SpeechMode.wake) {
          _mode = SpeechMode.listening;
          _events.add(const WakeDetected('PUSH_TO_TALK'));
        }
      });
    }
  }

  void _resetCaptureBuffer() {
    _meter.reset();
    _preRoll.clear();
    _preRollLength = 0;
    _speechBuffer.clear();
    _voicedFrames = 0;
    _silentFramesAfterSpeech = 0;
    _peakSpeechDbfs = -100.0;
    _speechDetected = false;
    _transcribing = false;
  }

  /// Immediately submits any buffered speech when the user taps the mic again
  /// to finish their turn early.
  bool flushUtterance() {
    if (_disposed ||
        !_initialized ||
        _mode != SpeechMode.listening ||
        _transcribing ||
        !_speechDetected ||
        _speechBuffer.isEmpty) {
      return false;
    }
    _submitUtterance();
    return true;
  }

  @override
  void addAudio(Uint8List bytes) {
    if (_disposed ||
        !_initialized ||
        _mode != SpeechMode.listening ||
        _transcribing ||
        bytes.isEmpty) {
      return;
    }
    if (bytes.length > 64000) {
      _fail(VoiceFailure.processingOverrun);
      return;
    }

    final readings = _meter.add(bytes);
    for (final reading in readings) {
      if (!_speechDetected) {
        if (reading.rmsDbfs >= speechThresholdDbfs) {
          _speechDetected = true;
          _events.add(const SpeechStarted());
          _voicedFrames = 0;
          _silentFramesAfterSpeech = 0;
          _peakSpeechDbfs = reading.rmsDbfs;
          for (final chunk in _preRoll) {
            _speechBuffer.add(chunk);
          }
          _preRoll.clear();
          _preRollLength = 0;
        } else {
          continue;
        }
      }
      if (reading.rmsDbfs > _peakSpeechDbfs) {
        _peakSpeechDbfs = reading.rmsDbfs;
      }
      // Adaptive silence check: allow a full 20 dB speech dynamic range and
      // clamp to <= -39 dBFS so softer words or trailing syllables after an
      // initial loud word are never mistaken for silence mid-sentence.
      final adaptiveSilenceFloor = (_peakSpeechDbfs - 20.0).clamp(
        silenceThresholdDbfs,
        -39.0,
      );
      final effectiveSilenceThreshold =
          adaptiveSilenceFloor > silenceThresholdDbfs
          ? adaptiveSilenceFloor
          : silenceThresholdDbfs;
      if (reading.rmsDbfs >= effectiveSilenceThreshold) {
        _voicedFrames++;
        _silentFramesAfterSpeech = 0;
      } else {
        _silentFramesAfterSpeech++;
      }
    }

    if (!_speechDetected) {
      _retainPreRoll(bytes);
      return;
    }

    _speechBuffer.add(bytes);

    final reachedSilenceEndpoint =
        _voicedFrames >= minSpeechFrames &&
        _silentFramesAfterSpeech >= silenceEndpointFrames;
    final reachedMaxDuration = _speechBuffer.length >= maxUtteranceBytes;

    if (reachedSilenceEndpoint) {
      _submitUtterance();
    } else if (reachedMaxDuration) {
      // Never interpret a forced prefix as the user's complete instruction.
      _fail(VoiceFailure.utteranceTooLong);
    }
  }

  void _retainPreRoll(Uint8List bytes) {
    final copy = Uint8List.fromList(
      bytes.length > _preRollBytes
          ? bytes.sublist(bytes.length - _preRollBytes)
          : bytes,
    );
    _preRoll.add(copy);
    _preRollLength += copy.length;
    while (_preRollLength > _preRollBytes && _preRoll.isNotEmpty) {
      final first = _preRoll.removeFirst();
      final excess = _preRollLength - _preRollBytes;
      if (first.length > excess) {
        _preRoll.addFirst(Uint8List.fromList(first.sublist(excess)));
        _preRollLength -= excess;
      } else {
        _preRollLength -= first.length;
      }
    }
  }

  static bool _isSilenceHallucination(String rawText, double peakDbfs) {
    final cleaned = rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    if (cleaned.isEmpty) return true;
    // Whisper commonly hallucinates these phrases on quiet background noise.
    if (peakDbfs < -33.0 &&
        const {
          'thank you',
          'thanks for watching',
          'thank you for watching',
          'subtitles by',
          'you',
          'the',
          'bye',
          'amaraorg',
        }.contains(cleaned)) {
      return true;
    }
    return false;
  }

  void _submitUtterance() {
    if (_disposed || _transcribing || _speechBuffer.isEmpty) return;
    _transcribing = true;
    _events.add(const TranscriptionStarted());
    final epoch = _epoch;
    final peakDbfs = _peakSpeechDbfs;
    final pcmBytes = normalizePcm16Mono(_speechBuffer.takeBytes());
    final wavBytes = encodePcm16MonoWav(pcmBytes);

    unawaited(() async {
      final clock = Stopwatch()..start();
      try {
        final response = await _http.postMultipart(
          uri: _endpoint,
          headers: {if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey'},
          fields: {
            'model': model,
            'language': 'en',
            'response_format': 'json',
            'temperature': '0',
            if (prompt.isNotEmpty) 'prompt': prompt,
          },
          fileField: 'file',
          fileName: 'turn.wav',
          contentType: 'audio/wav',
          fileBytes: wavBytes,
          timeout: requestTimeout,
        );
        if (_disposed || epoch != _epoch || _mode != SpeechMode.listening) {
          return;
        }
        if (!response.isSuccess) {
          _fail(VoiceFailure.unavailable);
          return;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          _fail(VoiceFailure.unavailable);
          return;
        }
        final rawText = (decoded['text'] as String? ?? '').trim();
        if (_isSilenceHallucination(rawText, peakDbfs)) {
          // Ignore quiet room-noise hallucinations and keep listening in-turn.
          _resetCaptureBuffer();
          _events.add(const ListeningResumed());
          return;
        }
        final text = LagosGazetteer.normalizeTranscript(rawText);
        if (_diagnostics) {
          developer.log(
            'engine=groq_whisper latencyMs=${clock.elapsedMilliseconds} audioBytes=${pcmBytes.length}',
            name: 'NAVI.voice',
          );
        }
        _mode = SpeechMode.muted;
        if (text.isNotEmpty) {
          _events.add(TranscriptChanged(text));
        }
        _events.add(UtteranceEnded(text));
      } catch (_) {
        if (!_disposed && epoch == _epoch) {
          _fail(VoiceFailure.unavailable);
        }
      }
    }());
  }

  void _fail(VoiceFailure failure) {
    if (_disposed) return;
    _mode = SpeechMode.muted;
    _epoch++;
    _resetCaptureBuffer();
    _events.add(SpeechFailed(failure));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _resetCaptureBuffer();
    if (_ownsHttp) _http.close();
    await _events.close();
  }
}
