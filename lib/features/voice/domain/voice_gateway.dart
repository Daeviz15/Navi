import 'dart:typed_data';

import 'voice_types.dart';

abstract interface class MicrophoneInput {
  Future<bool> hasPermission({required bool request});
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class SpeechEngine {
  Stream<SpeechEvent> get events;
  Future<void> initialize();
  void setMode(SpeechMode mode);
  void addAudio(Uint8List bytes);
  Future<void> dispose();
}

/// Playback events carry utterance IDs so late native callbacks are harmless.
abstract interface class VoiceGateway {
  Stream<OutputEvent> get events;
  Future<void> initialize();
  Future<void> speak(String message, {required int id});
  Future<void> stopSpeaking();
  Future<void> dispose();
}

abstract interface class VoicePreferences {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool enabled);
}
