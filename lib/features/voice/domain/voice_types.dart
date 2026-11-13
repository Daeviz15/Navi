import '../../journey/domain/journey_identity.dart';

enum SpeechMode { wake, listening, muted }

enum VoicePhase {
  off,
  preparing,
  listening,
  transcribing,
  preparingReply,
  speaking,
  suspended,
  error,
}

enum VoiceFailure {
  permissionDenied,
  unavailable,
  model,
  microphone,
  interrupted,
  processingOverrun,
  utteranceTooLong,
  offlineVoiceMissing,
  output,
  startupTimeout,
  wakeModelMissing,
}

class VoiceException implements Exception {
  const VoiceException(this.failure);
  final VoiceFailure failure;
}

sealed class SpeechEvent {
  const SpeechEvent();
}

class SpeechStarted extends SpeechEvent {
  const SpeechStarted();
}

class TranscriptionStarted extends SpeechEvent {
  const TranscriptionStarted();
}

class ListeningResumed extends SpeechEvent {
  const ListeningResumed({this.needsRepeat = false});
  final bool needsRepeat;
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
    this.journeyIdentity,
    this.enabled = false,
    this.phase = VoicePhase.off,
    this.transcript = '',
    this.reply = '',
    this.failure,
    this.destination,
    this.destinationRevision = 0,
    this.purposeSummary,
    this.isCasual = false,
    this.checklist = const <String>[],
    this.checklistRevision = 0,
    this.tripChangeRevision = 0,
    this.routeLaunchRevision = 0,
    this.endTripRevision = 0,
  });

  final JourneyIdentity? journeyIdentity;
  final bool enabled;
  final VoicePhase phase;
  final String transcript;
  final String reply;
  final VoiceFailure? failure;
  final String? destination;
  final int destinationRevision;
  final String? purposeSummary;
  final bool isCasual;
  final List<String> checklist;
  final int checklistRevision;
  final int tripChangeRevision;
  final int routeLaunchRevision;
  final int endTripRevision;

  String get caption => switch (phase) {
    VoicePhase.off => reply.isNotEmpty ? reply : 'Tap Navi to talk.',
    VoicePhase.preparing => 'Getting ready to listen on this device…',
    VoicePhase.listening =>
      transcript.isEmpty
          ? 'I’m listening. Tap Navi again to stop.'
          : transcript,
    VoicePhase.transcribing => 'I heard you. One moment…',
    VoicePhase.preparingReply => reply.isEmpty ? 'One moment…' : reply,
    VoicePhase.speaking => reply,
    VoicePhase.suspended => 'Conversation paused.',
    VoicePhase.error => switch (failure) {
      VoiceFailure.wakeModelMissing =>
        'Navi’s wake model is missing from this build.',
      VoiceFailure.startupTimeout =>
        'Getting ready took too long. Tap Navi to try again.',
      VoiceFailure.permissionDenied =>
        'Allow microphone access to talk to Navi.',
      VoiceFailure.offlineVoiceMissing =>
        'Install an offline English voice in your phone’s speech settings.',
      VoiceFailure.processingOverrun =>
        'Audio processing fell behind. Try again in a quieter place.',
      VoiceFailure.utteranceTooLong =>
        'That was a long turn. Try a shorter request so I catch it all.',
      VoiceFailure.interrupted =>
        'The microphone was interrupted. Tap to reconnect.',
      VoiceFailure.model =>
        'The local speech model could not load. Try restarting the app.',
      VoiceFailure.unavailable =>
        'Voice services could not connect. Check your connection and try again.',
      _ => 'Voice could not continue. Tap Navi to try again.',
    },
  };
}
