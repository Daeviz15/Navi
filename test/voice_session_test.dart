import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/character/domain/navi_clip.dart';
import 'package:navi/features/character/presentation/companion_controller.dart';
import 'package:navi/features/voice/application/voice_dependencies.dart';
import 'package:navi/features/voice/application/voice_session_controller.dart';
import 'package:navi/features/voice/domain/voice_gateway.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

void main() {
  test(
    'late output preparation failure is reported on reply without delaying wake readiness',
    () async {
      final gate = Completer<void>();
      final harness = Harness(outputGate: gate);
      addTearDown(harness.container.dispose);
      await harness.start();
      expect(harness.microphone.running, isTrue);
      gate.completeError(
        const VoiceException(VoiceFailure.offlineVoiceMissing),
      );
      await Future<void>.delayed(Duration.zero);
      harness.speech.emit(const WakeDetected('HEY_NAVI'));
      harness.speech.emit(const UtteranceEnded('Hey Navi'));
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.phase, VoicePhase.error);
      expect(harness.state.failure, VoiceFailure.offlineVoiceMissing);
      expect(harness.microphone.running, isFalse);
      await harness.controller.setEnabled(false);
    },
  );

  test(
    'wake capture starts without waiting for speech output initialization',
    () async {
      final speechGate = Completer<void>();
      final outputGate = Completer<void>();
      final harness = Harness(speechGate: speechGate, outputGate: outputGate);
      addTearDown(harness.container.dispose);
      harness.controller.setHomeVisible(true);
      await Future<void>.delayed(Duration.zero);
      final enabling = harness.controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(harness.speech.initialized, isTrue);
      expect(harness.output.initialized, isTrue);
      expect(harness.microphone.starts, 0);
      speechGate.complete();
      await enabling;
      expect(harness.state.phase, VoicePhase.armed);
      expect(harness.microphone.running, isTrue);
      expect(outputGate.isCompleted, isFalse);
      outputGate.complete();
      await harness.controller.setEnabled(false);
    },
  );

  test('a slow preference write does not delay microphone startup', () async {
    final preferenceGate = Completer<void>();
    final harness = Harness(preferenceGate: preferenceGate);
    addTearDown(() {
      if (!preferenceGate.isCompleted) preferenceGate.complete();
      harness.container.dispose();
    });
    await harness.start();
    expect(preferenceGate.isCompleted, isFalse);
    expect(harness.microphone.running, isTrue);
    preferenceGate.complete();
    await harness.controller.setEnabled(false);
  });

  test(
    'startup is bounded and a stalled voice engine releases the session',
    () async {
      final gate = Completer<void>();
      final harness = Harness(
        speechGate: gate,
        startupTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(harness.container.dispose);
      harness.controller.setHomeVisible(true);
      await Future<void>.delayed(Duration.zero);
      await harness.controller.setEnabled(true);
      expect(harness.state.phase, VoicePhase.error);
      expect(harness.state.failure, VoiceFailure.startupTimeout);
      expect(harness.microphone.starts, 0);
      expect(harness.output.disposed, isTrue);
    },
  );

  test(
    'confirmed wake plus an uncertain transcript acknowledges the user without changing a destination',
    () async {
      final harness = Harness();
      addTearDown(harness.container.dispose);
      await harness.start();
      harness.speech.emit(const WakeDetected('HEY_NAVI'));
      harness.speech.emit(const UtteranceEnded('I LOVE YOU'));
      await Future<void>.delayed(Duration.zero);
      expect(
        harness.output.messages.single,
        "Hey, I'm listening. Where would you like to go?",
      );
      expect(harness.state.destination, isNull);
      await harness.controller.setEnabled(false);
    },
  );
  test('opt-in is required; denial never initializes native speech', () async {
    final harness = Harness(permission: false);
    addTearDown(harness.container.dispose);
    harness.controller.setHomeVisible(true);
    await Future<void>.delayed(Duration.zero);
    expect(harness.microphones, isEmpty);
    await harness.controller.setEnabled(true, requestPermission: true);
    expect(harness.state.failure, VoiceFailure.permissionDenied);
    expect(harness.microphones.single.requested, isTrue);
    expect(harness.speeches.single.initialized, isFalse);
    expect(harness.microphones.single.running, isFalse);
    expect(harness.outputs.single.disposed, isTrue);
  });

  test(
    'greeting waits for audio start, ignores duplicates and rearms after silence',
    () async {
      final harness = Harness();
      addTearDown(harness.container.dispose);
      await harness.start();
      final companion = harness.container.read(companionProvider.notifier);
      harness.speech.emit(const WakeDetected('HEY_NAVI'));
      expect(harness.state.phase, VoicePhase.listening);
      expect(harness.frame.clip, NaviClips.listening);
      companion.touched();
      expect(harness.frame.clip, NaviClips.listening);
      harness.speech.emit(const UtteranceEnded('HEY NAVIG'));
      harness.speech.emit(const UtteranceEnded('HEY NAVIG'));
      await Future<void>.delayed(Duration.zero);
      expect(harness.output.messages, ['Hey! Where are we heading?']);
      expect(harness.microphone.running, isFalse);
      expect(harness.speech.mode, SpeechMode.muted);
      expect(harness.frame.clip, NaviClips.thinking);
      harness.output.emit(
        OutputEvent(harness.output.id! + 1, OutputEventType.started),
      );
      expect(harness.state.phase, VoicePhase.preparingReply);
      harness.output.started();
      expect(harness.state.phase, VoicePhase.speaking);
      expect(harness.frame.clip, NaviClips.speaking);
      final oldRevision = harness.frame.revision;
      companion.clipCompleted(oldRevision - 1);
      companion.touched();
      expect(harness.frame.clip, NaviClips.speaking);
      harness.output.finish();
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.phase, VoicePhase.listening);
      expect(harness.microphone.running, isTrue);
      await Future<void>.delayed(VoiceSessionController.followUpTimeout);
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.phase, VoicePhase.armed);
      expect(harness.output.messages, hasLength(1));
      await harness.controller.setEnabled(false);
    },
  );

  test(
    'one wake utterance fills a destination without launching navigation',
    () async {
      final harness = Harness();
      addTearDown(harness.container.dispose);
      await harness.start();
      harness.speech.emit(const WakeDetected('HI_NAVI'));
      harness.speech.emit(const TranscriptChanged('Hi Navi take me to Lekki'));
      expect(harness.state.transcript, 'take me to Lekki');
      harness.speech.emit(const UtteranceEnded('Hi Navi take me to Lekki'));
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.destination, 'Lekki');
      expect(harness.state.destinationRevision, 1);
      harness.output.started();
      harness.output.finish();
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.phase, VoicePhase.armed);
      await harness.controller.setEnabled(false);
    },
  );

  test(
    'background and screen departure release resources; resume creates a fresh session',
    () async {
      final harness = Harness();
      addTearDown(harness.container.dispose);
      await harness.start();
      harness.speech.emit(const WakeDetected('HEY_NAVI'));
      harness.speech.emit(const UtteranceEnded('hello navi'));
      await Future<void>.delayed(Duration.zero);
      final oldOutput = harness.output;
      harness.controller.setForeground(false);
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.phase, VoicePhase.suspended);
      expect(harness.state.enabled, isTrue);
      expect(oldOutput.disposed, isTrue);
      expect(harness.microphone.running, isFalse);
      harness.controller.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(harness.microphones, hasLength(2));
      expect(harness.state.phase, VoicePhase.armed);
      harness.controller.suspendForNavigation();
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.phase, VoicePhase.suspended);
      expect(harness.microphone.running, isFalse);
    },
  );

  test('sleep command disables hands-free after the reply', () async {
    final harness = Harness();
    addTearDown(harness.container.dispose);
    await harness.start();
    harness.speech.emit(const WakeDetected('HEY_NAVI'));
    harness.speech.emit(const UtteranceEnded('Hey Navi stop listening'));
    await Future<void>.delayed(Duration.zero);
    harness.output.started();
    harness.output.finish();
    await Future<void>.delayed(Duration.zero);
    expect(harness.state.phase, VoicePhase.off);
    expect(harness.preferences.enabled, isFalse);
    expect(harness.microphone.running, isFalse);
  });

  test('restored opt-in checks permission without requesting it', () async {
    final harness = Harness(permission: false, restored: true);
    addTearDown(harness.container.dispose);
    harness.controller.setHomeVisible(true);
    await Future<void>.delayed(Duration.zero);
    expect(harness.state.phase, VoicePhase.error);
    expect(harness.microphones.single.requested, isFalse);
    await harness.controller.setEnabled(false);
  });

  test('capture failure stops playback and reports the failure', () async {
    final harness = Harness();
    addTearDown(harness.container.dispose);
    await harness.start();
    harness.speech.emit(const SpeechFailed(VoiceFailure.processingOverrun));
    await Future<void>.delayed(Duration.zero);
    expect(harness.state.failure, VoiceFailure.processingOverrun);
    expect(harness.microphone.disposed, isTrue);
    expect(harness.output.disposed, isTrue);
    await harness.controller.setEnabled(false);
  });

  test(
    'disabling during initialization cancels startup without starting the microphone',
    () async {
      final gate = Completer<void>();
      final harness = Harness(speechGate: gate);
      addTearDown(harness.container.dispose);
      harness.controller.setHomeVisible(true);
      await Future<void>.delayed(Duration.zero);
      final enabling = harness.controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(harness.state.phase, VoicePhase.preparing);
      final disabling = harness.controller.setEnabled(false);
      await Future<void>.delayed(Duration.zero);
      await Future.wait([enabling, disabling]);
      expect(harness.state.phase, VoicePhase.off);
      expect(harness.microphone.starts, 0);
      expect(harness.output.disposed, isTrue);
    },
  );

  test(
    'live microphone chunks drive voiceAudioLevelProvider and reset on reply or disable',
    () async {
      final harness = Harness();
      addTearDown(harness.container.dispose);
      await harness.start();
      final level = harness.container.read(voiceAudioLevelProvider);
      expect(level.value, 0.0);

      final loudChunk = ByteData(1600);
      for (var i = 0; i < 800; i++) {
        loudChunk.setInt16(i * 2, 8192, Endian.little);
      }
      harness.microphone.audio.add(loudChunk.buffer.asUint8List());
      await Future<void>.delayed(Duration.zero);
      expect(level.value, greaterThan(0.4));

      harness.speech.emit(const WakeDetected('HEY_NAVI'));
      harness.speech.emit(const UtteranceEnded('Hey Navi'));
      await Future<void>.delayed(Duration.zero);
      expect(level.value, 0.0);
      await harness.controller.setEnabled(false);
    },
  );
}

class Harness {
  Harness({
    this.permission = true,
    bool restored = false,
    this.outputGate,
    this.speechGate,
    Completer<void>? preferenceGate,
    Duration startupTimeout = const Duration(seconds: 10),
  }) {
    preferences = FakePreferences(restored, preferenceGate);
    container = ProviderContainer(
      overrides: [
        voiceServicesProvider.overrideWithValue(
          VoiceServices(
            microphone: () {
              final input = FakeMicrophone(permission);
              microphones.add(input);
              return input;
            },
            speech: () {
              final engine = FakeSpeech(speechGate);
              speeches.add(engine);
              return engine;
            },
            output: () {
              final voice = FakeOutput(outputGate);
              outputs.add(voice);
              return voice;
            },
            preferences: preferences,
            startupTimeout: startupTimeout,
          ),
        ),
      ],
    );
    controller = container.read(voiceSessionProvider.notifier);
  }
  final bool permission;
  final Completer<void>? outputGate;
  final Completer<void>? speechGate;
  late final FakePreferences preferences;
  late final ProviderContainer container;
  late final VoiceSessionController controller;
  final microphones = <FakeMicrophone>[];
  final speeches = <FakeSpeech>[];
  final outputs = <FakeOutput>[];
  FakeMicrophone get microphone => microphones.last;
  FakeSpeech get speech => speeches.last;
  FakeOutput get output => outputs.last;
  VoiceSessionState get state => container.read(voiceSessionProvider);
  CompanionFrame get frame => container.read(companionProvider);
  Future<void> start() async {
    container.listen(companionProvider, (_, _) {});
    controller.setHomeVisible(true);
    await Future<void>.delayed(Duration.zero);
    await controller.setEnabled(true, requestPermission: true);
    expect(state.phase, VoicePhase.armed);
  }
}

class FakePreferences implements VoicePreferences {
  FakePreferences(this.enabled, [this.gate]);
  final Completer<void>? gate;
  bool enabled;
  @override
  Future<bool> readEnabled() async => enabled;
  @override
  Future<void> writeEnabled(bool value) async {
    await gate?.future;
    enabled = value;
  }
}

class FakeMicrophone implements MicrophoneInput {
  FakeMicrophone(this.permission);
  final bool permission;
  bool requested = false, running = false, disposed = false;
  int starts = 0;
  final audio = StreamController<Uint8List>.broadcast();
  @override
  Future<bool> hasPermission({required bool request}) async {
    requested = request;
    return permission;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    running = true;
    starts++;
    return audio.stream;
  }

  @override
  Future<void> stop() async {
    running = false;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    running = false;
    await audio.close();
  }
}

class FakeSpeech implements SpeechEngine {
  FakeSpeech([this.gate]);
  final Completer<void>? gate;
  final stream = StreamController<SpeechEvent>.broadcast(sync: true);
  bool initialized = false;
  SpeechMode mode = SpeechMode.muted;
  void emit(SpeechEvent event) => stream.add(event);
  @override
  Stream<SpeechEvent> get events => stream.stream;
  @override
  Future<void> initialize() async {
    initialized = true;
    await gate?.future;
  }

  @override
  void setMode(SpeechMode value) {
    mode = value;
  }

  @override
  void addAudio(Uint8List bytes) {}
  @override
  Future<void> dispose() async {
    await stream.close();
  }
}

class FakeOutput implements VoiceGateway {
  FakeOutput(this.gate);
  final Completer<void>? gate;
  final stream = StreamController<OutputEvent>.broadcast(sync: true);
  final messages = <String>[];
  Completer<void>? completion;
  bool disposed = false, initialized = false;
  int? id;
  void emit(OutputEvent event) => stream.add(event);
  void started() => emit(OutputEvent(id!, OutputEventType.started));
  void finish() {
    emit(OutputEvent(id!, OutputEventType.completed));
    completion!.complete();
    completion = null;
  }

  @override
  Stream<OutputEvent> get events => stream.stream;
  @override
  Future<void> initialize() async {
    initialized = true;
    await gate?.future;
  }

  @override
  Future<void> speak(String text, {required int id}) {
    this.id = id;
    messages.add(text);
    completion = Completer<void>();
    return completion!.future;
  }

  @override
  Future<void> stopSpeaking() async {
    completion?.complete();
    completion = null;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (gate != null && !gate!.isCompleted) gate!.complete();
    await stopSpeaking();
    await stream.close();
  }
}
