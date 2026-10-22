enum SpeechMode { wake, listening, muted }

enum VoicePhase { off, preparing, armed, listening, preparingReply, speaking, suspended, error }

enum VoiceFailure {
  permissionDenied,
  unavailable,
  model,
  microphone,
  interrupted,
  processingOverrun,
  offlineVoiceMissing,
  output,
}

class VoiceException implements Exception {
  const VoiceException(this.failure);
  final VoiceFailure failure;
}

sealed class SpeechEvent {
  const SpeechEvent();
}

class WakeDetected extends SpeechEvent {
  const WakeDetected(this.phrase);
  final String phrase;
}

class TranscriptChanged extends SpeechEvent {
  const TranscriptChanged(this.text);
  final String text;
}

class UtteranceEnded extends SpeechEvent {
  const UtteranceEnded(this.text);
  final String text;
}

class SpeechFailed extends SpeechEvent {
  const SpeechFailed(this.failure);
  final VoiceFailure failure;
}

enum OutputEventType { started, completed, cancelled, failed }

class OutputEvent {
  const OutputEvent(this.id, this.type);
  final int id;
  final OutputEventType type;
}

class VoiceSessionState {
  const VoiceSessionState({
    this.enabled = false,
    this.phase = VoicePhase.off,
    this.transcript = '',
    this.reply = '',
    this.failure,
    this.destination,
    this.destinationRevision = 0,
  });

  final bool enabled;
  final VoicePhase phase;
  final String transcript;
  final String reply;
  final VoiceFailure? failure;
  final String? destination;
  final int destinationRevision;

  String get caption => switch (phase) {
    VoicePhase.off => 'No rush. Ready when you are.',
    VoicePhase.preparing => 'Getting ready to listen on this device…',
    VoicePhase.armed => 'Say “Hey Navi” or “Hi Navi”.',
    VoicePhase.listening => transcript.isEmpty ? 'I’m listening.' : transcript,
    VoicePhase.preparingReply => 'One moment…',
    VoicePhase.speaking => reply,
    VoicePhase.suspended => 'Hands-free is paused.',
    VoicePhase.error => switch (failure) {
      VoiceFailure.permissionDenied => 'Allow microphone access to talk to Navi.',
      VoiceFailure.offlineVoiceMissing => 'Install an offline English voice in your phone’s speech settings.',
      VoiceFailure.processingOverrun => 'Audio processing fell behind. Try again in a quieter place.',
      VoiceFailure.interrupted => 'The microphone was interrupted. Tap to reconnect.',
      VoiceFailure.model => 'The local speech model could not load. Try restarting the app.',
      VoiceFailure.unavailable => 'Hands-free is available on Android in this version.',
      _ => 'Hands-free could not continue. Tap to retry.',
    },
  };
}
