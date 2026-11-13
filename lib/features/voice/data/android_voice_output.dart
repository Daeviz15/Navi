import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'cloud_http_client.dart';
import 'wav_encoder.dart';

/// Three-tier neural voice output:
/// 1. Primary: Canopy Labs Orpheus (`canopylabs/orpheus-v1-english`, voice `hannah`) on Groq
///    played natively via Android `AudioTrack`.
/// 2. Cloud Fallback: Google Cloud Text-to-Speech (`en-US-Chirp3-HD-Kore` with 1M chars/mo free).
/// 3. Offline Fallback: Android's native high-quality neural/offline TTS.
class AndroidVoiceOutput implements VoiceGateway {
  AndroidVoiceOutput({
    String? groqApiKey,
    String? googleApiKey,
    String? androidPackage,
    String? androidCert,
    this.ttsModel = const String.fromEnvironment(
      'NAVI_GROQ_TTS_MODEL',
      defaultValue: 'canopylabs/orpheus-v1-english',
    ),
    this.ttsVoice = const String.fromEnvironment(
      'NAVI_GROQ_TTS_VOICE',
      defaultValue: 'hannah',
    ),
    this.googleTtsVoice = const String.fromEnvironment(
      'NAVI_GOOGLE_TTS_VOICE',
      defaultValue: 'en-US-Chirp3-HD-Kore',
    ),
    CloudHttpTransport? http,
  }) : _groqApiKey =
           (groqApiKey ?? const String.fromEnvironment('GROQ_API_KEY')).trim(),
       _googleApiKey =
           (googleApiKey ??
                   const String.fromEnvironment(
                     'GOOGLE_TTS_API_KEY',
                     defaultValue: String.fromEnvironment('GOOGLE_MAPS_API'),
                   ))
               .trim(),
       _androidPackage = (androidPackage ?? '').trim(),
       _androidCert = (androidCert ?? '').trim(),
       _http = http ?? DartIoCloudHttpTransport(),
       _ownsHttp = http == null;

  static const _channel = MethodChannel('navi/voice_output');
  static final _ttsEndpoint = Uri.parse(
    'https://api.groq.com/openai/v1/audio/speech',
  );
  static final _googleTtsEndpoint = Uri.parse(
    'https://texttospeech.googleapis.com/v1/text:synthesize',
  );
  static const _backchannelCues = <String>[
    'Mm-hmm.',
    'Yeah...',
    'True...',
    'Right...',
  ];
  static bool _orpheusUnavailable = false;
  static bool _googleTtsUnavailable = false;
  static bool _warmingBackchannels = false;
  static int _fillerIndex = 0;
  static DateTime? _orpheusCooldownUntil;
  static DateTime? _googleTtsCooldownUntil;
  static final Map<String, Uint8List> _wavCache = <String, Uint8List>{};

  final String ttsModel;
  final String ttsVoice;
  final String googleTtsVoice;
  String _groqApiKey;
  String _googleApiKey;
  String _androidPackage;
  String _androidCert;
  final CloudHttpTransport _http;
  final bool _ownsHttp;
  final _events = StreamController<OutputEvent>.broadcast();
  Completer<void>? _completion;
  int? _activeId;
  bool _ready = false;
  bool _attached = false;
  bool _disposed = false;

  @override
  Stream<OutputEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_disposed) throw const VoiceException(VoiceFailure.interrupted);
    if (_ready) return;
    if (!Platform.isAndroid) {
      throw const VoiceException(VoiceFailure.unavailable);
    }
    if (_groqApiKey.isEmpty && _http is DartIoCloudHttpTransport) {
      _groqApiKey = await CloudEnvConfig.resolveKey(
        'GROQ_API_KEY',
        _groqApiKey,
      );
    }
    if (_googleApiKey.isEmpty && _http is DartIoCloudHttpTransport) {
      _googleApiKey = await CloudEnvConfig.resolveKey(
        'GOOGLE_TTS_API_KEY',
        _googleApiKey,
      );
      if (_googleApiKey.isEmpty) {
        _googleApiKey = await CloudEnvConfig.resolveKey(
          'GOOGLE_MAPS_API',
          _googleApiKey,
        );
      }
    }
    // A tap can cancel speech-only guidance while credentials are resolving.
    // A disposed output must never replace the next session's channel handler.
    if (_disposed) throw const VoiceException(VoiceFailure.interrupted);
    _channel.setMethodCallHandler(_onEvent);
    _attached = true;
    try {
      final credentials = await _channel
          .invokeMethod<Map<Object?, Object?>>('initialize')
          .timeout(const Duration(seconds: 15));
      if (credentials != null) {
        if (_androidPackage.isEmpty) {
          _androidPackage = credentials['package']?.toString() ?? '';
        }
        if (_androidCert.isEmpty) {
          _androidCert = credentials['cert']?.toString() ?? '';
        }
      }
      if (_disposed) throw const VoiceException(VoiceFailure.interrupted);
      _ready = true;
      unawaited(_loadDiskCachedBackchannels());
    } on PlatformException catch (error) {
      throw VoiceException(
        error.code == 'offline_voice_missing'
            ? VoiceFailure.offlineVoiceMissing
            : VoiceFailure.output,
      );
    }
  }

  Future<void> _onEvent(MethodCall call) async {
    if (_disposed || call.arguments is! Map) return;
    final arguments = Map<Object?, Object?>.from(call.arguments as Map);
    final id = int.tryParse(arguments['id'].toString());
    if (id == null || id != _activeId) return;
    final type = switch (call.method) {
      'started' => OutputEventType.started,
      'completed' => OutputEventType.completed,
      'cancelled' => OutputEventType.cancelled,
      _ => OutputEventType.failed,
    };
    _events.add(OutputEvent(id, type));
    if (type != OutputEventType.started) {
      final completion = _completion;
      _completion = null;
      _activeId = null;
      if (completion != null && !completion.isCompleted) {
        if (type == OutputEventType.failed) {
          completion.completeError(const VoiceException(VoiceFailure.output));
        } else {
          completion.complete();
        }
      }
    }
  }

  /// Loads any previously cached backchannel WAVs from device disk without
  /// making network calls that would consume Groq Orpheus's per-minute quota.
  Future<void> _loadDiskCachedBackchannels() async {
    if (_warmingBackchannels) return;
    _warmingBackchannels = true;
    try {
      for (final cue in _backchannelCues) {
        if (_disposed) break;
        if (_wavCache.containsKey(cue)) continue;
        final diskFile = _diskCacheFile(ttsVoice, cue);
        if (diskFile != null && await diskFile.exists()) {
          final bytes = await diskFile.readAsBytes();
          if (bytes.length > 44) {
            _wavCache[cue] = bytes;
          }
        }
      }
    } catch (_) {
    } finally {
      _warmingBackchannels = false;
    }
  }

  /// Plays a pre-cached 0.4s natural backchannel ("Mm-hmm.", "Yeah...",
  /// "True...", "Right...") in 0 ms while the LLM and TTS prepare the main
  /// conversational response.
  void playBackchannelFiller() {
    if (_disposed || !_ready || _activeId != null) return;
    for (var i = 0; i < _backchannelCues.length; i++) {
      final cue =
          _backchannelCues[(_fillerIndex + i) % _backchannelCues.length];
      final bytes = _wavCache[cue];
      if (bytes != null) {
        _fillerIndex = (_fillerIndex + i + 1) % _backchannelCues.length;
        unawaited(
          _channel
              .invokeMethod<void>('playFillerWav', {'bytes': bytes})
              .catchError((Object _) {}),
        );
        return;
      }
    }
  }

  static File? _diskCacheFile(String voice, String message) {
    try {
      var hash = 0x811c9dc5;
      final key = '$voice|$message';
      for (var i = 0; i < key.length; i++) {
        hash ^= key.codeUnitAt(i);
        hash = (hash * 0x01000193) & 0x7fffffff;
      }
      final dir = Directory('${Directory.systemTemp.path}/navi_tts_cache_v1');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/tts_${hash.toRadixString(16)}.wav');
    } catch (_) {
      return null;
    }
  }

  static String _clampOrpheusInput(String message) {
    final clean = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.length <= 195) return clean;
    final slice = clean.substring(0, 195);
    final lastPunct = slice.lastIndexOf(RegExp(r'[.!?]'));
    if (lastPunct >= 80) {
      return slice.substring(0, lastPunct + 1).trim();
    }
    final lastSpace = slice.lastIndexOf(' ');
    return (lastSpace > 80 ? slice.substring(0, lastSpace) : slice).trim();
  }

  Future<Uint8List?> _synthesizeOrpheusWav(String message) async {
    final ttsInput = _clampOrpheusInput(message);
    if (_orpheusUnavailable || _groqApiKey.isEmpty || ttsInput.isEmpty) {
      return null;
    }
    final cached = _wavCache[ttsInput];
    if (cached != null) return cached;

    final diskFile = _diskCacheFile(ttsVoice, ttsInput);
    if (diskFile != null) {
      try {
        if (await diskFile.exists()) {
          final diskBytes = await diskFile.readAsBytes();
          if (diskBytes.length > 44) {
            if (_wavCache.length >= 24) {
              _wavCache.remove(_wavCache.keys.first);
            }
            _wavCache[ttsInput] = diskBytes;
            return diskBytes;
          }
        }
      } catch (_) {}
    }

    // Respect Groq's rate limits: after a 429, skip Orpheus for a cooldown
    // window so each turn falls back instantly instead of waiting on a
    // request that is guaranteed to be rejected.
    final cooldown = _orpheusCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      return null;
    }

    if (_disposed) return null;
    try {
      final res = await _http.postJsonBytes(
        uri: _ttsEndpoint,
        headers: {'Authorization': 'Bearer $_groqApiKey'},
        body: {
          'model': ttsModel,
          'input': ttsInput,
          'voice': ttsVoice,
          'response_format': 'wav',
        },
        timeout: const Duration(seconds: 8),
      );
      if (res.isSuccess && res.bytes.length > 44) {
        _orpheusCooldownUntil = null;
        final normalized = normalizeStreamingWav(res.bytes);
        if (normalized != null) {
          if (_wavCache.length >= 24) {
            _wavCache.remove(_wavCache.keys.first);
          }
          _wavCache[ttsInput] = normalized;
          if (diskFile != null) {
            unawaited(
              diskFile
                  .writeAsBytes(normalized, flush: true)
                  .catchError((_) => diskFile),
            );
          }
        }
        return normalized;
      }
      if (res.statusCode == 429) {
        _orpheusCooldownUntil = DateTime.now().add(const Duration(minutes: 5));
      } else if (res.statusCode == 401) {
        _orpheusUnavailable = true;
      }
    } catch (_) {
      // Fall through to Google Cloud TTS or Android offline TTS.
    }
    return null;
  }

  Future<Uint8List?> _synthesizeGoogleCloudWav(String message) async {
    final ttsInput = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_googleTtsUnavailable || _googleApiKey.isEmpty || ttsInput.isEmpty) {
      return null;
    }
    final cacheKey = 'google|$googleTtsVoice|$ttsInput';
    final cached = _wavCache[cacheKey];
    if (cached != null) return cached;

    final diskFile = _diskCacheFile('google_$googleTtsVoice', ttsInput);
    if (diskFile != null) {
      try {
        if (await diskFile.exists()) {
          final diskBytes = await diskFile.readAsBytes();
          if (diskBytes.length > 44) {
            if (_wavCache.length >= 24) {
              _wavCache.remove(_wavCache.keys.first);
            }
            _wavCache[cacheKey] = diskBytes;
            return diskBytes;
          }
        }
      } catch (_) {}
    }

    final cooldown = _googleTtsCooldownUntil;
    if (cooldown != null && DateTime.now().isBefore(cooldown)) {
      return null;
    }

    if (_disposed) return null;
    try {
      final res = await _http.postJsonBytes(
        uri: _googleTtsEndpoint,
        headers: {
          'X-Goog-Api-Key': _googleApiKey,
          if (_androidPackage.isNotEmpty) 'X-Android-Package': _androidPackage,
          if (_androidCert.isNotEmpty) 'X-Android-Cert': _androidCert,
        },
        body: {
          'input': {'text': ttsInput},
          'voice': {'languageCode': 'en-US', 'name': googleTtsVoice},
          'audioConfig': {
            'audioEncoding': 'LINEAR16',
            'sampleRateHertz': 24000,
          },
        },
        timeout: const Duration(seconds: 8),
      );

      if (res.isSuccess && res.bytes.isNotEmpty) {
        final decoded = jsonDecode(utf8.decode(res.bytes));
        if (decoded is Map && decoded['audioContent'] is String) {
          final rawWav = base64Decode(decoded['audioContent'] as String);
          if (rawWav.length > 44) {
            _googleTtsCooldownUntil = null;
            final normalized = normalizeStreamingWav(rawWav) ?? rawWav;
            if (_wavCache.length >= 24) {
              _wavCache.remove(_wavCache.keys.first);
            }
            _wavCache[cacheKey] = normalized;
            if (diskFile != null) {
              unawaited(
                diskFile
                    .writeAsBytes(normalized, flush: true)
                    .catchError((_) => diskFile),
              );
            }
            return normalized;
          }
        }
      }

      if (res.statusCode == 429) {
        _googleTtsCooldownUntil = DateTime.now().add(
          const Duration(minutes: 5),
        );
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        // Cloud Text-to-Speech is blocked or disabled on this key; skip future
        // calls in this session and fall through directly to offline TTS.
        _googleTtsUnavailable = true;
      }
    } catch (_) {
      // Fall through cleanly to Android native offline TTS.
    }
    return null;
  }

  /// Synthesizes speech using the 3-tier waterfall:
  /// 1. Groq Orpheus ("hannah")
  /// 2. Google Cloud TTS ("en-US-Chirp3-HD-Kore")
  /// 3. Returns null to trigger native Android offline TTS
  Future<Uint8List?> synthesizeWav(String message) async {
    var wav = await _synthesizeOrpheusWav(message);
    wav ??= await _synthesizeGoogleCloudWav(message);
    return wav;
  }

  static void resetStateForTesting() {
    _orpheusUnavailable = false;
    _googleTtsUnavailable = false;
    _orpheusCooldownUntil = null;
    _googleTtsCooldownUntil = null;
    _wavCache.clear();
    try {
      final dir = Directory('${Directory.systemTemp.path}/navi_tts_cache_v1');
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } catch (_) {}
  }

  @override
  Future<void> speak(String message, {required int id}) async {
    if (!_ready) await initialize();
    await stopSpeaking();
    final wavBytes = await synthesizeWav(message);
    if (_disposed) throw const VoiceException(VoiceFailure.interrupted);
    final completion = _completion = Completer<void>();
    _activeId = id;
    // Attach the error listener before dispatching to the platform.
    final finished = completion.future.timeout(const Duration(seconds: 30));
    try {
      await Future.wait<void>([
        if (wavBytes != null)
          _channel.invokeMethod<void>('playWav', {
            'id': '$id',
            'bytes': wavBytes,
            'text': message,
          })
        else
          _channel.invokeMethod<void>('speak', {'id': '$id', 'text': message}),
        finished,
      ], eagerError: true);
    } catch (_) {
      if (_activeId == id) await stopSpeaking();
      throw const VoiceException(VoiceFailure.output);
    }
  }

  @override
  Future<void> stopSpeaking() async {
    _activeId = null;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) completion.complete();
    if (_ready) await _channel.invokeMethod<void>('stop');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await stopSpeaking();
      if (_attached) await _channel.invokeMethod<void>('dispose');
    } finally {
      if (_attached) _channel.setMethodCallHandler(null);
      if (_ownsHttp) _http.close();
      await _events.close();
      _ready = false;
    }
  }
}
