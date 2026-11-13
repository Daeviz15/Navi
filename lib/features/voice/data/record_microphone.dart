import 'dart:async';
import 'dart:typed_data';
import 'dart:developer' as developer;

import 'package:record/record.dart';

import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'pcm_audio_levels.dart';

class RecordMicrophone implements MicrophoneInput {
  AudioRecorder? _recorder;
  StreamIterator<Uint8List>? _capture;
  bool _running = false;
  bool _disposed = false;
  Future<void> _operations = Future.value();

  AudioRecorder get _audio {
    if (_disposed) throw const VoiceException(VoiceFailure.interrupted);
    return _recorder ??= AudioRecorder();
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  @override
  Future<bool> hasPermission({required bool request}) =>
      _audio.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> start() => _serialize(() async {
    if (_running) throw StateError('Microphone already running');
    final startup = Stopwatch()..start();
    await _audio.setOnConfigChanged((config) {
      if (config.sampleRate != 16000 ||
          config.numChannels != 1 ||
          config.encoder != AudioEncoder.pcm16bits) {
        // A changed format cannot safely be fed into the recognizer.
        _formatInvalid = true;
      }
    });
    _formatInvalid = false;
    final stream = await _audio.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        streamBufferSize: 3200,
        // Request hardware gain and noise suppression where supported. Capture
        // and playback are exclusive, so echo cancellation is unnecessary and
        // can suppress quiet speech on some Android devices.
        autoGain: true,
        echoCancel: false,
        noiseSuppress: true,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
        audioInterruption: AudioInterruptionMode.none,
      ),
    );
    _running = true;
    final capture = StreamIterator(stream);
    _capture = capture;
    Uint8List first;
    try {
      // Publish “listening” only once the native microphone delivers PCM.
      // Preserve this first buffer, including words spoken during startup.
      do {
        if (!await capture.moveNext().timeout(const Duration(seconds: 3))) {
          throw const VoiceException(VoiceFailure.microphone);
        }
        first = capture.current;
      } while (first.isEmpty);
    } catch (_) {
      await _stop();
      rethrow;
    }
    var firstBuffer = true;
    final meter = const bool.fromEnvironment('NAVI_VOICE_DIAGNOSTICS')
        ? PcmAudioMeter()
        : null;
    Stream<Uint8List> frames() async* {
      yield first;
      while (await capture.moveNext()) {
        yield capture.current;
      }
    }

    return frames().map((bytes) {
      if (_formatInvalid) throw const VoiceException(VoiceFailure.microphone);
      if (firstBuffer && bytes.isNotEmpty) {
        firstBuffer = false;
        if (const bool.fromEnvironment('NAVI_VOICE_DIAGNOSTICS')) {
          developer.log(
            'stage=mic_ready startupMs=${startup.elapsedMilliseconds}',
            name: 'NAVI.voice',
          );
        }
      }
      if (meter != null) {
        for (final levels in meter.add(bytes)) {
          developer.log(
            'mic=16000Hz/mono/PCM16 rmsDbfs=${levels.rmsDbfs.toStringAsFixed(1)} '
            'peakDbfs=${levels.peakDbfs.toStringAsFixed(1)} clipped=${levels.clippedSamples}',
            name: 'NAVI.voice',
          );
        }
      }
      return bytes;
    });
  });

  bool _formatInvalid = false;

  @override
  Future<void> stop() => _serialize(_stop);

  Future<void> _stop() async {
    final recorder = _recorder;
    if (recorder == null || !_running) return;
    _running = false;
    await _capture?.cancel();
    _capture = null;
    try {
      // Release capture for playback, but reuse the native recorder for the
      // next turn instead of recreating its platform channels every time.
      await recorder.stop();
    } catch (_) {
      // A recorder that failed to stop must be recreated on the next start.
      _recorder = null;
      try {
        await recorder.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() => _serialize(() async {
    if (_disposed) return;
    _disposed = true;
    await _stop();
    await _recorder?.dispose();
    _recorder = null;
  });
}
