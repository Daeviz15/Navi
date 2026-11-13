import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/application/voice_journey_bridge.dart';
import 'package:navi/features/journey/domain/journey_identity.dart';
import 'package:navi/features/journey/presentation/journey_controller.dart';
import 'package:navi/features/voice/domain/local_command_router.dart';
import 'package:navi/features/voice/domain/voice_gateway.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

import 'support/voice_harness.dart';

void main() {
  test('uncertain speech keeps the tapped session open and displays a repeat prompt', () async {
    final h = VoiceHarness();
    addTearDown(h.container.dispose);
    await h.start();
    h.speech.emit(const TranscriptionStarted());
    await flushVoice();
    h.speech.emit(const ListeningResumed(needsRepeat: true));
    await flushVoice();
    expect(h.state.phase, VoicePhase.listening);
    expect(h.state.caption, contains('Please say it again'));
    expect(h.state.enabled, isTrue);
    expect(h.microphone.running, isTrue);
  });
  test(
    'an external trip edit cancels an old reply and cannot apply its destination',
    () async {
      final reasoner = QueueReasoner([])..pending = Completer<LocalReply>();
      final h = VoiceHarness(reasoner: reasoner);
      addTearDown(h.container.dispose);
      h.container.listen(voiceJourneyBridgeProvider, (_, _) {});
      final journey = h.container.read(journeyDraftProvider.notifier);
      journey.setDestination('Ikeja');
      await h.start();
      await h.turn('Where am I heading?');
      expect(h.state.phase, VoicePhase.preparingReply);
      journey.setDestination('Yaba');
      await flushVoice();
      expect(h.state.enabled, isFalse);
      reasoner.pending!.complete(
        const LocalReply(
          LocalIntent.destination,
          'Going to the old place',
          destination: 'Lekki',
        ),
      );
      await flushVoice();
      expect(h.container.read(journeyDraftProvider).destination, 'Yaba');
      expect(h.state.reply, isEmpty);
      expect(h.outputs.every((output) => output.messages.isEmpty), isTrue);
      await h.controller.toggleConversation();
      expect(h.state.phase, VoicePhase.listening);
      expect(
        h.state.journeyIdentity,
        h.container.read(journeyDraftProvider).identity,
      );
    },
  );

  test(
    'telemetry updates in the same trip do not interrupt listening',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      const identity = JourneyIdentity(tripId: 5, intentRevision: 2);
      h.controller.updateTransitContext(
        const JourneyTransitContext(
          identity: identity,
          isActive: true,
          destination: 'Ikeja',
        ),
      );
      await h.start();
      h.controller.updateTransitContext(
        const JourneyTransitContext(
          identity: identity,
          isActive: true,
          destination: 'Ikeja',
          currentArea: 'Yaba',
        ),
      );
      expect(h.state.enabled, isTrue);
      expect(h.state.phase, VoicePhase.listening);
      expect(h.microphone.disposed, isFalse);
    },
  );

  test(
    'a selected map destination can complete with a purpose-only reply',
    () async {
      final h = VoiceHarness(
        reasoner: QueueReasoner([
          const LocalReply(
            LocalIntent.purpose,
            'Ready for your interview.',
            purposeSummary: 'Job interview',
            checklist: ['CV'],
          ),
        ]),
      );
      addTearDown(h.container.dispose);
      h.controller.setSurfaceVisible('journey', true);
      await flushVoice();
      await h.controller.toggleConversation(destination: 'Ikeja');
      await h.turn('I am going for an interview');
      await h.finishReply();
      expect(h.state.enabled, isFalse);
      expect(h.state.destination, 'Ikeja');
      expect(h.state.purposeSummary, 'Job interview');
    },
  );

  test(
    'stalled startup reports an error and cannot open capture late',
    () async {
      final gate = Completer<void>();
      final h = VoiceHarness(
        speechGate: gate,
        startupTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(h.container.dispose);
      h.controller.setHomeVisible(true);
      await flushVoice();
      final start = h.controller.toggleConversation();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(h.state.failure, VoiceFailure.startupTimeout);
      expect(h.state.enabled, isFalse);
      expect(h.microphone.starts, 0);
      gate.complete();
      await start.timeout(const Duration(seconds: 1));
    },
  );

  test('showing Navi never opens the microphone without a tap', () async {
    final h = VoiceHarness();
    addTearDown(h.container.dispose);
    h.controller.setHomeVisible(true);
    h.controller.setSurfaceVisible('journey', true);
    await flushVoice();
    expect(h.state.enabled, isFalse);
    expect(h.microphones, isEmpty);
    h.controller.setForeground(false);
    h.controller.setForeground(true);
    await flushVoice();
    expect(h.microphones, isEmpty);
    await h.controller.toggleConversation();
    expect(h.state.phase, VoicePhase.listening);
    expect(h.microphone.requested, isTrue);
  });

  test(
    'a tap opens capture without waiting for output initialization',
    () async {
      final gate = Completer<void>();
      final h = VoiceHarness(outputGate: gate);
      addTearDown(h.container.dispose);
      await h.start();
      expect(h.state.phase, VoicePhase.listening);
      expect(h.microphone.running, isTrue);
      gate.complete();
    },
  );

  test(
    'permission denial releases capture and waits for another tap',
    () async {
      final h = VoiceHarness(permission: false);
      addTearDown(h.container.dispose);
      await h.start();
      expect(h.state.phase, VoicePhase.error);
      expect(h.state.enabled, isFalse);
      expect(h.microphone.disposed, isTrue);
      expect(h.microphone.starts, 0);
      expect(h.speech.initialized, isFalse);
      h.controller.setForeground(false);
      h.controller.setForeground(true);
      await flushVoice();
      expect(h.microphones, hasLength(1));
    },
  );

  test(
    'permission-dialog inactivity does not cancel a deliberate tap',
    () async {
      final gate = Completer<void>();
      final h = VoiceHarness(permissionGate: gate);
      addTearDown(h.container.dispose);
      h.controller.setHomeVisible(true);
      await flushVoice();
      final start = h.controller.toggleConversation();
      await flushVoice();
      h.controller.setForeground(false, transient: true);
      gate.complete();
      await start;
      expect(h.state.phase, VoicePhase.listening);
      expect(h.microphone.running, isTrue);
    },
  );

  test('second tap during startup cancels late initialization', () async {
    final gate = Completer<void>();
    final h = VoiceHarness(speechGate: gate);
    addTearDown(h.container.dispose);
    h.controller.setHomeVisible(true);
    await flushVoice();
    final start = h.controller.toggleConversation();
    await flushVoice();
    await h.controller.toggleConversation();
    gate.complete();
    await start;
    await flushVoice();
    expect(h.state.phase, VoicePhase.off);
    expect(h.microphone.starts, 0);
    expect(h.microphone.disposed, isTrue);
  });

  test(
    'second tap during microphone startup cannot leave late capture running',
    () async {
      final gate = Completer<void>();
      final h = VoiceHarness(captureGate: gate);
      addTearDown(h.container.dispose);
      h.controller.setHomeVisible(true);
      await flushVoice();
      final start = h.controller.toggleConversation();
      await flushVoice();
      await h.controller.toggleConversation();
      gate.complete();
      await start;
      await flushVoice();
      expect(h.state.enabled, isFalse);
      expect(h.microphone.running, isFalse);
    },
  );

  testWidgets('a quiet minute does not stop a tapped conversation', (
    tester,
  ) async {
    final h = VoiceHarness();
    h.controller.setHomeVisible(true);
    await tester.pump();
    final start = h.controller.toggleConversation();
    await tester.pump();
    await start;
    await tester.pump(const Duration(minutes: 1));
    expect(h.state.phase, VoicePhase.listening);
    expect(h.state.enabled, isTrue);
    expect(h.microphone.running, isTrue);
    h.container.dispose();
    await tester.pump();
  });

  test(
    'destination alone stays active despite a false follow-up flag; purpose completes after playback',
    () async {
      final h = VoiceHarness(
        reasoner: QueueReasoner([
          const LocalReply(
            LocalIntent.destination,
            'What brings you there?',
            destination: 'Ikeja',
            followUp: false,
          ),
          const LocalReply(
            LocalIntent.purpose,
            'Your essentials are ready.',
            purposeSummary: 'SIM registration',
            checklist: ['NIN', 'ID'],
            followUp: true,
          ),
        ]),
      );
      addTearDown(h.container.dispose);
      h.container.listen(voiceJourneyBridgeProvider, (_, _) {});
      await h.start();
      await h.turn('Take me to Ikeja');
      expect(h.microphone.running, isFalse); // No capture during Navi's reply.
      await h.finishReply();
      expect(h.state.phase, VoicePhase.listening);
      expect(h.state.enabled, isTrue);
      await h.turn('I need a new SIM');
      expect(h.state.enabled, isTrue); // Let the final confirmation finish.
      expect(h.state.checklist, ['NIN', 'ID']);
      await h.finishReply();
      expect(h.state.phase, VoicePhase.off);
      expect(h.microphone.running, isFalse);
      expect(h.state.reply, 'Your essentials are ready.');
      expect(
        h.container.read(journeyDraftProvider).purposeSummary,
        'SIM registration',
      );
    },
  );

  test('casual purpose completes without requiring a checklist', () async {
    final h = VoiceHarness(
      reasoner: QueueReasoner([
        const LocalReply(
          LocalIntent.destination,
          'Enjoy your visit!',
          destination: 'Yaba',
          purposeSummary: 'Visiting a friend',
          isCasual: true,
        ),
      ]),
    );
    addTearDown(h.container.dispose);
    await h.start();
    await h.turn('I am visiting a friend in Yaba');
    await h.finishReply();
    expect(h.state.enabled, isFalse);
    expect(h.state.checklist, isEmpty);
    expect(h.state.isCasual, isTrue);
  });

  test(
    'purpose supplied before destination survives into the locked journey',
    () async {
      final h = VoiceHarness(
        reasoner: QueueReasoner([
          const LocalReply(
            LocalIntent.purpose,
            'Where is the interview?',
            purposeSummary: 'Job interview',
            checklist: ['CV'],
          ),
          const LocalReply(
            LocalIntent.destination,
            'Ikeja, got it.',
            destination: 'Ikeja',
          ),
        ]),
      );
      addTearDown(h.container.dispose);
      h.container.listen(voiceJourneyBridgeProvider, (_, _) {});
      await h.start();
      await h.turn('I have an interview');
      await h.finishReply();
      expect(h.state.enabled, isTrue);
      await h.turn('In Ikeja');
      await h.finishReply();
      expect(h.state.enabled, isFalse);
      expect(
        h.container.read(journeyDraftProvider).purposeSummary,
        'Job interview',
      );
      expect(h.state.checklist, ['CV']);
    },
  );

  test(
    'second tap stops playback instead of restarting the microphone',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      await h.start();
      await h.turn('Hello Navi');
      h.output.started();
      expect(h.state.phase, VoicePhase.speaking);
      await h.controller.toggleConversation();
      await flushVoice();
      expect(h.state.phase, VoicePhase.off);
      expect(h.microphone.starts, 1);
      expect(h.output.disposed, isTrue);
    },
  );

  test(
    'second tap while transcribing cancels rather than flushing the utterance',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      await h.start();
      h.speech.emit(const SpeechStarted());
      h.speech.emit(const TranscriptionStarted());
      expect(h.state.phase, VoicePhase.transcribing);
      await h.controller.toggleConversation();
      expect(h.state.phase, VoicePhase.off);
      expect(h.output.messages, isEmpty);
    },
  );

  test(
    'late model completion after a stop cannot change the journey or speak',
    () async {
      final reasoner = QueueReasoner([])..pending = Completer<LocalReply>();
      final h = VoiceHarness(reasoner: reasoner);
      addTearDown(h.container.dispose);
      h.container.listen(voiceJourneyBridgeProvider, (_, _) {});
      await h.start();
      await h.turn('My trip request');
      await h.controller.toggleConversation();
      reasoner.pending!.complete(
        const LocalReply(
          LocalIntent.destination,
          'Ready.',
          destination: 'Ikeja',
          purposeSummary: 'Interview',
        ),
      );
      await flushVoice();
      expect(h.state.destination, isNull);
      expect(h.container.read(journeyDraftProvider).destination, isEmpty);
      expect(h.output.messages, isEmpty);
    },
  );

  test(
    'backgrounding stops capture and returning never starts it without another tap',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      await h.start();
      h.controller.setForeground(false);
      await flushVoice();
      expect(h.microphone.running, isFalse);
      expect(h.state.enabled, isFalse);
      h.controller.setForeground(true);
      await flushVoice();
      expect(h.microphones, hasLength(1));
      await h.controller.toggleConversation();
      expect(h.microphones, hasLength(2));
      expect(h.microphone.running, isTrue);
    },
  );

  test(
    'home-to-map ownership handoff preserves the same active conversation',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      await h.start();
      h.controller.setSurfaceVisible('journey', true);
      h.controller.setHomeVisible(false);
      await flushVoice();
      expect(h.state.phase, VoicePhase.listening);
      expect(h.microphone.starts, 1);
      await h.controller.toggleConversation();
      expect(h.microphone.running, isFalse);
    },
  );

  test(
    'a new tap does not reuse an old purpose to finish on a greeting',
    () async {
      final h = VoiceHarness(
        reasoner: QueueReasoner([
          const LocalReply(
            LocalIntent.destination,
            'Ready.',
            destination: 'Ikeja',
            purposeSummary: 'Interview',
          ),
          const LocalReply(
            LocalIntent.greeting,
            'Where to?',
            destination: 'Ikeja',
            purposeSummary: 'Interview',
            followUp: false,
          ),
        ]),
      );
      addTearDown(h.container.dispose);
      await h.start();
      await h.turn('Interview in Ikeja');
      await h.finishReply();
      expect(h.state.enabled, isFalse);
      await h.controller.toggleConversation();
      await h.turn('Hello');
      await h.finishReply();
      expect(h.state.enabled, isTrue);
      expect(h.state.phase, VoicePhase.listening);
    },
  );

  test(
    'transcription resumes after empty speech and answers each final event once',
    () async {
      final reasoner = QueueReasoner([
        const LocalReply(LocalIntent.clarify, 'Which place?'),
      ]);
      final h = VoiceHarness(reasoner: reasoner);
      addTearDown(h.container.dispose);
      await h.start();
      h.speech.emit(const SpeechStarted());
      h.speech.emit(const TranscriptionStarted());
      h.speech.emit(const ListeningResumed());
      expect(h.state.phase, VoicePhase.listening);
      await h.turn('');
      expect(h.output.messages, isEmpty);
      h.speech.emit(const UtteranceEnded('some place'));
      h.speech.emit(const UtteranceEnded('some place'));
      await flushVoice();
      expect(reasoner.calls, 1);
      expect(h.output.messages, hasLength(1));
    },
  );

  test(
    'capture failure releases resources and waits for an explicit tap',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      await h.start();
      h.speech.emit(const SpeechFailed(VoiceFailure.processingOverrun));
      await flushVoice();
      expect(h.state.phase, VoicePhase.error);
      expect(h.state.enabled, isFalse);
      expect(h.microphone.disposed, isTrue);
    },
  );

  test('microphone energy follows capture and resets on stop', () async {
    final h = VoiceHarness();
    addTearDown(h.container.dispose);
    await h.start();
    final bytes = ByteData(1600);
    for (var i = 0; i < 800; i++) {
      bytes.setInt16(i * 2, 12000, Endian.little);
    }
    h.microphone.audio.add(bytes.buffer.asUint8List());
    expect(h.controller.audioLevel.value, greaterThan(0));
    await h.controller.toggleConversation();
    expect(h.controller.audioLevel.value, 0);
  });

  test(
    'active transit Q&A stays open across follow-up turns without closing early',
    () async {
      final reasoner = _ConversationAwareQueueReasoner([
        const LocalReply(
          LocalIntent.clarify,
          'You are near Admiralty Way, about 1.4 km from Lekki Phase 1.',
          purposeSummary: 'Client meeting',
          followUp: true,
        ),
        const LocalReply(
          LocalIntent.clarify,
          'Keep heading straight along Admiralty Way.',
          purposeSummary: 'Client meeting',
          followUp: true,
        ),
      ]);
      final h = VoiceHarness(reasoner: reasoner);
      addTearDown(h.container.dispose);
      h.controller.updateTransitContext(
        const JourneyTransitContext(
          isActive: true,
          destination: 'Lekki Phase 1',
          currentArea: 'Admiralty Way',
          remainingDistanceMeters: 1400,
          remainingDurationSeconds: 360,
          purposeSummary: 'Client meeting',
        ),
      );
      expect(reasoner.transitUpdates, isNotEmpty);

      await h.start();
      await h.turn('Where am I right now?');
      await h.finishReply();
      expect(h.state.enabled, isTrue);
      expect(h.state.phase, VoicePhase.listening);

      await h.turn('Should I turn soon?');
      await h.finishReply();
      expect(h.state.enabled, isTrue);
      expect(h.state.phase, VoicePhase.listening);
      expect(h.state.tripChangeRevision, 0);
      expect(h.state.endTripRevision, 0);
    },
  );

  test(
    'mid-trip change emits tripChangeRevision and routeLaunchRevision and updates draft',
    () async {
      final reasoner = _ConversationAwareQueueReasoner([
        const LocalReply(
          LocalIntent.clarify,
          'Okay, changing to Ikeja. What for?',
          destination: 'Ikeja',
          changeTrip: true,
          followUp: true,
        ),
        const LocalReply(
          LocalIntent.purpose,
          'Got it, preparing your route to Ikeja.',
          destination: 'Ikeja',
          purposeSummary: 'Swap SIM card',
          checklist: ['NIN', 'ID card'],
          changeTrip: true,
          followUp: false,
        ),
      ]);
      final h = VoiceHarness(reasoner: reasoner);
      addTearDown(h.container.dispose);
      h.container.listen(voiceJourneyBridgeProvider, (_, _) {});
      h.controller.updateTransitContext(
        const JourneyTransitContext(
          isActive: true,
          destination: 'Lekki Phase 1',
          currentArea: 'Admiralty Way',
          remainingDistanceMeters: 1400,
          remainingDurationSeconds: 360,
          purposeSummary: 'Client meeting',
        ),
      );

      await h.start();
      await h.turn('Change my trip to Ikeja');
      await h.finishReply();
      expect(h.state.enabled, isTrue);
      expect(h.state.tripChangeRevision, 1);
      expect(h.state.routeLaunchRevision, 0);

      await h.turn('To swap my SIM card');
      await h.finishReply();
      expect(h.state.tripChangeRevision, greaterThanOrEqualTo(1));
      expect(h.state.routeLaunchRevision, 1);
      expect(h.state.enabled, isFalse);

      final draft = h.container.read(journeyDraftProvider);
      expect(draft.destination, 'Ikeja');
      expect(draft.purposeSummary, 'Swap SIM card');
      expect(draft.checklist, ['NIN', 'ID card']);
    },
  );

  test('explicit endTrip emits endTripRevision after TTS finishes', () async {
    final reasoner = _ConversationAwareQueueReasoner([
      const LocalReply(
        LocalIntent.clarify,
        'Ending your trip now.',
        endTrip: true,
        followUp: false,
      ),
    ]);
    final h = VoiceHarness(reasoner: reasoner);
    addTearDown(h.container.dispose);
    h.container.listen(voiceJourneyBridgeProvider, (_, _) {});
    h.controller.updateTransitContext(
      const JourneyTransitContext(
        isActive: true,
        destination: 'Lekki Phase 1',
        currentArea: 'Admiralty Way',
        remainingDistanceMeters: 500,
        remainingDurationSeconds: 120,
      ),
    );

    await h.start();
    await h.turn('End my trip');
    await h.finishReply();
    expect(h.state.endTripRevision, 1);
    expect(h.state.enabled, isFalse);
  });
}

class _ConversationAwareQueueReasoner extends QueueReasoner
    implements ConversationAwareReasoner {
  _ConversationAwareQueueReasoner(super.replies);

  final List<JourneyTransitContext> transitUpdates = <JourneyTransitContext>[];
  String? selectedDestination;
  int clearCalls = 0;

  @override
  void setDestinationContext(String destination) {
    selectedDestination = destination;
  }

  @override
  void updateTransitContext(
    JourneyTransitContext context, {
    bool resetPendingSwitch = false,
  }) {
    transitUpdates.add(context);
  }

  @override
  void clearTripContext() {
    clearCalls++;
  }

  @override
  void cancelPendingReply() {}
}
