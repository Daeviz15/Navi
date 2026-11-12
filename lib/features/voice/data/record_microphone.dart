import 'dart:typed_data';
import 'dart:developer' as developer;

import 'package:record/record.dart';

import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';
import 'pcm_audio_levels.dart';

class RecordMicrophone implements MicrophoneInput {
  AudioRecorder? _recorder;
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
        autoGain: true,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.mic,
        ),
        audioInterruption: AudioInterruptionMode.none,
      ),
    );
    _running = true;
    final meter = const bool.fromEnvironment('NAVI_VOICE_DIAGNOSTICS')
        ? PcmAudioMeter()
        : null;
    return stream.map((bytes) {
      if (_formatInvalid) throw const VoiceException(VoiceFailure.microphone);
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
    _recorder = null;
    if (recorder != null) {
      if (_running) {
        _running = false;
        try {
          await recorder.stop();
        } catch (_) {}
      }
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
