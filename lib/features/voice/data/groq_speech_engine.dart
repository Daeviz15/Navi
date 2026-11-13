import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/lagos_gazetteer.dart';
import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'cloud_http_client.dart';
import 'pcm_audio_levels.dart';
import 'wav_encoder.dart';

/// Tap-activated, turn-based cloud speech engine backed by Groq Whisper
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
  int _consecutiveVoiceDuringPause = 0;
  int _warmupFrames = 0;
  double _warmupMinDbfs = 0.0;
  double _warmupMaxDbfs = -100.0;
  double _peakSpeechDbfs = -100.0;
  double _minSpeechWindowDbfs = 0.0;
  double _noiseFloorDbfs = -60.0;
  bool _hasNoiseEstimate = false;
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
    _noiseFloorDbfs = -60.0;
    _hasNoiseEstimate = false;
    _warmupFrames = 0;
    _warmupMinDbfs = 0.0;
    _warmupMaxDbfs = -100.0;
    _resetCaptureBuffer();
  }

  void _resetCaptureBuffer() {
    _meter.reset();
    _preRoll.clear();
    _preRollLength = 0;
    _speechBuffer.clear();
    _voicedFrames = 0;
    _silentFramesAfterSpeech = 0;
    _consecutiveVoiceDuringPause = 0;
    _peakSpeechDbfs = -100.0;
    _minSpeechWindowDbfs = 0.0;
    _speechDetected = false;
    _transcribing = false;
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
        if (!_hasNoiseEstimate &&
            reading.rmsDbfs >= speechThresholdDbfs &&
            reading.rmsDbfs < -25.0) {
          _warmupFrames++;
          _warmupMinDbfs = math.min(_warmupMinDbfs, reading.rmsDbfs);
          _warmupMaxDbfs = math.max(_warmupMaxDbfs, reading.rmsDbfs);
          if (_warmupFrames < 3 && (_warmupMaxDbfs - _warmupMinDbfs) <= 4.0) {
            continue;
          }
          if ((_warmupMaxDbfs - _warmupMinDbfs) <= 4.0) {
            _noiseFloorDbfs = _warmupMinDbfs.clamp(-75.0, -28.0);
            _hasNoiseEstimate = true;
            continue;
          }
        }
        final dynamicSpeechThreshold = _hasNoiseEstimate
            ? math.max(
                speechThresholdDbfs,
                (_noiseFloorDbfs + 7.0).clamp(-45.0, -24.0),
              )
            : speechThresholdDbfs;
        if (reading.rmsDbfs >= dynamicSpeechThreshold) {
          _speechDetected = true;
          _events.add(const SpeechStarted());
          _voicedFrames = 0;
          _silentFramesAfterSpeech = 0;
          _consecutiveVoiceDuringPause = 0;
          _peakSpeechDbfs = reading.rmsDbfs;
          _minSpeechWindowDbfs = reading.rmsDbfs;
          for (final chunk in _preRoll) {
            _speechBuffer.add(chunk);
          }
          _preRoll.clear();
          _preRollLength = 0;
          if (_diagnostics) {
            developer.log(
              'vad=speech_start rms=${reading.rmsDbfs.toStringAsFixed(1)} '
              'noiseFloor=${_noiseFloorDbfs.toStringAsFixed(1)} '
              'threshold=${dynamicSpeechThreshold.toStringAsFixed(1)}',
              name: 'NAVI.voice',
            );
          }
        } else {
          final clampedNoise = reading.rmsDbfs.clamp(-75.0, -28.0);
          if (!_hasNoiseEstimate) {
            _noiseFloorDbfs = clampedNoise;
            _hasNoiseEstimate = true;
          } else {
            final rate = clampedNoise < _noiseFloorDbfs ? 0.25 : 0.08;
            _noiseFloorDbfs += (clampedNoise - _noiseFloorDbfs) * rate;
          }
          continue;
        }
      }
      if (reading.rmsDbfs > _peakSpeechDbfs) {
        _peakSpeechDbfs = reading.rmsDbfs;
      }
      if (reading.rmsDbfs < _minSpeechWindowDbfs) {
        _minSpeechWindowDbfs = reading.rmsDbfs;
      }
      // Endpoint when energy drops well below speech peak OR settles back down
      // near the room's measured ambient noise floor.
      final peakDropFloor = (_peakSpeechDbfs - 16.0).clamp(
        silenceThresholdDbfs,
        -28.0,
      );
      final noiseReturnFloor = _hasNoiseEstimate
          ? (_noiseFloorDbfs + 4.0).clamp(silenceThresholdDbfs, -26.0)
          : silenceThresholdDbfs;
      final effectiveSilenceThreshold = math.max(
        silenceThresholdDbfs,
        math.max(peakDropFloor, noiseReturnFloor),
      );
      if (reading.rmsDbfs >= effectiveSilenceThreshold) {
        if (_silentFramesAfterSpeech == 0 ||
            _consecutiveVoiceDuringPause >= 1) {
          _voicedFrames++;
          _silentFramesAfterSpeech = 0;
          _consecutiveVoiceDuringPause = 0;
        } else {
          // Require two consecutive frames above threshold during a pause so
          // a single 50 ms click or breath does not reset endpointing.
          _consecutiveVoiceDuringPause++;
        }
      } else {
        _consecutiveVoiceDuringPause = 0;
        _silentFramesAfterSpeech++;
      }

      // Discard brief mechanical taps (< minSpeechFrames) followed by silence,
      // and recover if steady background noise triggered onset before noise
      // floor calibration had idle frames to measure.
      final briefFalseTrigger =
          _voicedFrames < minSpeechFrames && _silentFramesAfterSpeech >= 6;
      final steadyBackgroundNoise =
          !_hasNoiseEstimate &&
          _voicedFrames >= 40 &&
          (_peakSpeechDbfs - _minSpeechWindowDbfs) < 5.0 &&
          _peakSpeechDbfs < -25.0;
      if (briefFalseTrigger || steadyBackgroundNoise) {
        if (steadyBackgroundNoise) {
          _noiseFloorDbfs = _peakSpeechDbfs.clamp(-75.0, -28.0);
          _hasNoiseEstimate = true;
        }
        _speechBuffer.clear();
        _preRoll.clear();
        _preRollLength = 0;
        _voicedFrames = 0;
        _silentFramesAfterSpeech = 0;
        _consecutiveVoiceDuringPause = 0;
        _peakSpeechDbfs = -100.0;
        _minSpeechWindowDbfs = 0.0;
        _speechDetected = false;
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
    // Whisper commonly hallucinates these YouTube-style captions on noise.
    if (peakDbfs < -33.0 &&
        const {
          'thanks for watching',
          'thank you for watching',
          'subtitles by',
          'amaraorg',
        }.contains(cleaned)) {
      return true;
    }
    if (peakDbfs < -40.0 &&
        const {'thank you', 'you', 'the', 'bye'}.contains(cleaned)) {
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
          if (_diagnostics) {
            developer.log(
              'engine=groq_whisper httpStatus=${response.statusCode} body=${response.body}',
              name: 'NAVI.voice',
            );
          }
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
          if (_diagnostics) {
            developer.log(
              'engine=groq_whisper dropped_hallucination peakDbfs=${peakDbfs.toStringAsFixed(1)} text="$rawText"',
              name: 'NAVI.voice',
            );
          }
          _noiseFloorDbfs = math.max(
            _noiseFloorDbfs,
            (peakDbfs - 2.0).clamp(-65.0, -28.0),
          );
          _hasNoiseEstimate = true;
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
