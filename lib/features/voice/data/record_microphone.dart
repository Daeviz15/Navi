import 'dart:typed_data';

import 'package:record/record.dart';

import '../domain/voice_gateway.dart';
import '../domain/voice_types.dart';

class RecordMicrophone implements MicrophoneInput {
  AudioRecorder? _recorder;
  bool _running = false;

  AudioRecorder get _audio => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission({required bool request}) => _audio.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> start() async {
    if (_running) throw StateError('Microphone already running');
    await _audio.setOnConfigChanged((config) {
      if (config.sampleRate != 16000 || config.numChannels != 1 || config.encoder != AudioEncoder.pcm16bits) {
        // A changed format cannot safely be fed into the recognizer.
        _formatInvalid = true;
      }
    });
    _formatInvalid = false;
    final stream = await _audio.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1,
      streamBufferSize: 3200, noiseSuppress: true,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
      audioInterruption: AudioInterruptionMode.none,
    ));
    _running = true;
    return stream.map((bytes) {
      if (_formatInvalid) throw const VoiceException(VoiceFailure.microphone);
      return bytes;
    });
  }

  bool _formatInvalid = false;

  @override
  Future<void> stop() async {
    if (_recorder != null && _running) {
      _running = false;
      await _recorder!.stop();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _recorder?.dispose();
    _recorder = null;
  }
}
