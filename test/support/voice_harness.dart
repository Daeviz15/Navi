import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:navi/features/navigation/domain/destination_selection.dart';
import 'package:navi/features/voice/application/voice_dependencies.dart';
import 'package:navi/features/voice/application/voice_session_controller.dart';
import 'package:navi/features/voice/domain/local_command_router.dart';
import 'package:navi/features/voice/domain/voice_gateway.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

Future<void> flushVoice() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class VoiceHarness {
  VoiceHarness({
    VoiceReasoner reasoner = const LocalCommandRouter(),
    bool permission = true,
    Completer<void>? speechGate,
    Completer<void>? outputGate,
    Completer<void>? permissionGate,
    Completer<void>? captureGate,
    Duration startupTimeout = const Duration(seconds: 10),
    DestinationSelectionCommands? destinations,
  }) {
    container = ProviderContainer(
      overrides: [
        voiceServicesProvider.overrideWithValue(
          VoiceServices(
            microphone: () {
              final input = TestMicrophone(
                permission,
                permissionGate,
                captureGate,
              );
              microphones.add(input);
              return input;
            },
            speech: () {
              final engine = TestSpeech(speechGate);
              speeches.add(engine);
              return engine;
            },
            output: () {
              final output = TestVoiceOutput(outputGate);
              outputs.add(output);
              return output;
            },
            reasoner: reasoner,
            startupTimeout: startupTimeout,
            destinations: destinations,
          ),
        ),
      ],
    );
    controller = container.read(voiceSessionProvider.notifier);
  }
  late final ProviderContainer container;
  late final VoiceSessionController controller;
  final microphones = <TestMicrophone>[];
  final speeches = <TestSpeech>[];
  final outputs = <TestVoiceOutput>[];
  TestMicrophone get microphone => microphones.last;
  TestSpeech get speech => speeches.last;
  TestVoiceOutput get output => outputs.last;
  VoiceSessionState get state => container.read(voiceSessionProvider);
  Future<void> start() async {
    controller.setHomeVisible(true);
    await flushVoice();
    await controller.toggleConversation();
  }

  Future<void> turn(String words) async {
    speech.emit(UtteranceEnded(words));
    await flushVoice();
  }

  Future<void> finishReply() async {
    output.finish();
    await flushVoice();
  }
}

class QueueReasoner implements VoiceReasoner {
  QueueReasoner(this.replies);
  final List<LocalReply> replies;
  int calls = 0;
  Completer<LocalReply>? pending;
  @override
  Future<LocalReply> resolve(
    String utterance, {
    required bool wakeDetected,
  }) async {
    calls++;
    return pending?.future ?? Future.value(replies.removeAt(0));
  }
}

class TestMicrophone implements MicrophoneInput {
  TestMicrophone(this.permission, this.permissionGate, this.captureGate);
  final bool permission;
  final Completer<void>? permissionGate, captureGate;
  final audio = StreamController<Uint8List>.broadcast(sync: true);
  bool running = false, disposed = false, requested = false;
  int starts = 0;
  @override
  Future<bool> hasPermission({required bool request}) async {
    requested = request;
    await permissionGate?.future;
    return permission;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    await captureGate?.future;
    if (!disposed) running = true;
    return audio.stream;
  }

  @override
  Future<void> stop() async => running = false;
  @override
  Future<void> dispose() async {
    disposed = true;
    running = false;
    await audio.close();
  }
}

class TestSpeech implements SpeechEngine {
  TestSpeech(this.gate);
  final Completer<void>? gate;
  final stream = StreamController<SpeechEvent>.broadcast(sync: true);
  bool initialized = false, disposed = false;
  SpeechMode mode = SpeechMode.muted;
  void emit(SpeechEvent event) {
    if (!disposed) stream.add(event);
  }

  @override
  Stream<SpeechEvent> get events => stream.stream;
  @override
  Future<void> initialize() async {
    initialized = true;
    await gate?.future;
  }

  @override
  void setMode(SpeechMode value) => mode = value;
  @override
  void addAudio(Uint8List bytes) {}
  @override
  Future<void> dispose() async {
    disposed = true;
    await stream.close();
  }
}

class TestVoiceOutput implements VoiceGateway {
  TestVoiceOutput(this.gate);
  final Completer<void>? gate;
  final stream = StreamController<OutputEvent>.broadcast(sync: true);
  final messages = <String>[];
  Completer<void>? completion;
  int? id;
  bool disposed = false;
  void started() => stream.add(OutputEvent(id!, OutputEventType.started));
  void finish() {
    stream.add(OutputEvent(id!, OutputEventType.completed));
    completion?.complete();
    completion = null;
  }

  @override
  Stream<OutputEvent> get events => stream.stream;
  @override
  Future<void> initialize() async => await gate?.future;
  @override
  Future<void> speak(String message, {required int id}) {
    this.id = id;
    messages.add(message);
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
    await stopSpeaking();
    await stream.close();
  }
}
