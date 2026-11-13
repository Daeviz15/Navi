import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/domain/journey_identity.dart';
import 'package:navi/features/navigation/domain/destination_selection.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/voice/domain/destination_confirmation_policy.dart';
import 'package:navi/features/voice/domain/local_command_router.dart';
import 'package:navi/features/voice/domain/voice_gateway.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

import 'support/voice_harness.dart';

const _first = DestinationPlace(
  id: 'first',
  name: 'MTN office',
  address: 'Admiralty Way, Lekki, Lagos',
  point: GeoPoint(6.45, 3.47),
);
const _second = DestinationPlace(
  id: 'second',
  name: 'MTN office',
  address: 'Allen Avenue, Ikeja, Lagos',
  point: GeoPoint(6.6, 3.35),
);
const _identity = JourneyIdentity(tripId: 3);

DestinationSuggestions suggestions(int revision) => DestinationSuggestions(
  token: DestinationSearchToken(_identity, revision),
  places: const [_first, _second],
);

void context(VoiceHarness h, DestinationSuggestions matches) =>
    h.controller.updateTransitContext(
      JourneyTransitContext(
        identity: _identity,
        isActive: true,
        destination: 'MTN office',
        purposeSummary: 'SIM replacement',
        destinationSuggestions: matches,
      ),
    );

void main() {
  test('ambiguous names need an option; mixed agreement never confirms', () {
    const policy = DestinationConfirmationPolicy();
    final matches = suggestions(1);
    final ambiguous = policy.resolve(
      'MTN office',
      suggestions: matches,
      spokenPrompt: null,
    )!;
    expect(ambiguous.request, isNull);
    expect(ambiguous.prompt, isNull);
    final prompt = policy
        .resolve('option two', suggestions: matches, spokenPrompt: null)!
        .prompt!;
    for (final text in [
      'yes but use another branch',
      'I said no',
      'maybe',
      'yes change my trip to Yaba',
    ]) {
      expect(
        policy
            .resolve(text, suggestions: matches, spokenPrompt: prompt)
            ?.request,
        isNull,
      );
    }
    expect(
      policy
          .resolve(
            'Yes, that is the one!',
            suggestions: matches,
            spokenPrompt: prompt,
          )!
          .request!
          .placeId,
      _second.id,
    );
  });

  test(
    'yes requires a finished readback; confirmation bypasses the LLM',
    () async {
      final commands = _Commands();
      final reasoner = QueueReasoner([]);
      final h = VoiceHarness(reasoner: reasoner, destinations: commands);
      addTearDown(h.container.dispose);
      context(h, suggestions(1));
      await h.start();
      await h.turn('yes');
      expect(commands.confirmed, isEmpty);
      expect(h.state.reply, contains(_first.address));
      // Speech events while Navi is still playing the prompt cannot confirm it.
      await h.turn('yes');
      expect(commands.confirmed, isEmpty);
      await h.finishReply();
      await h.turn('yes');
      expect(commands.confirmed.single.placeId, _first.id);
      expect(
        commands.confirmed.single.source,
        DestinationConfirmationSource.voice,
      );
      await h.finishReply();
      expect(h.state.enabled, isFalse);
      expect(reasoner.calls, 0);
    },
  );

  test(
    'option two reads the full second address before accepting yes',
    () async {
      final commands = _Commands();
      final h = VoiceHarness(destinations: commands);
      addTearDown(h.container.dispose);
      context(h, suggestions(1));
      await h.start();
      await h.turn('the second one');
      expect(h.state.reply, contains(_second.address));
      expect(commands.confirmed, isEmpty);
      await h.finishReply();
      await h.turn('yes please');
      expect(commands.confirmed.single.placeId, _second.id);
      await h.finishReply();
    },
  );

  test('no rejects only the spoken place and keeps listening', () async {
    final commands = _Commands();
    final h = VoiceHarness(destinations: commands);
    addTearDown(h.container.dispose);
    context(h, suggestions(1));
    await h.start();
    await h.turn('option two');
    await h.finishReply();
    await h.turn('not that one');
    expect(commands.rejected.single.placeId, _second.id);
    expect(commands.confirmed, isEmpty);
    await h.finishReply();
    expect(h.state.phase, VoicePhase.listening);
  });

  test(
    'a fresh search invalidates an earlier readback, even for the same IDs',
    () async {
      final commands = _Commands();
      final h = VoiceHarness(destinations: commands);
      addTearDown(h.container.dispose);
      context(h, suggestions(1));
      await h.start();
      await h.turn('option two');
      await h.finishReply();
      context(h, suggestions(2));
      await h.turn('yes');
      expect(commands.confirmed, isEmpty);
      expect(h.state.reply, contains('Is that the place?'));
      await h.finishReply();
    },
  );

  test(
    'search changes during playback cannot make the old prompt confirmable',
    () async {
      final commands = _Commands();
      final h = VoiceHarness(destinations: commands);
      addTearDown(h.container.dispose);
      context(h, suggestions(1));
      await h.start();
      await h.turn('option two');
      context(h, suggestions(2));
      await h.finishReply();
      await h.turn('yes');
      expect(commands.confirmed, isEmpty);
      expect(h.state.reply, contains('Is that the place?'));
      await h.finishReply();
    },
  );

  test(
    'stopping and tapping again never carries a confirmation prompt across sessions',
    () async {
      final commands = _Commands();
      final h = VoiceHarness(destinations: commands);
      addTearDown(h.container.dispose);
      context(h, suggestions(1));
      await h.start();
      await h.turn('option two');
      await h.controller.toggleConversation();
      await h.controller.toggleConversation();
      await h.turn('yes');
      expect(commands.confirmed, isEmpty);
      expect(h.state.reply, contains('Is that the place?'));
      await h.finishReply();
    },
  );

  test(
    'rejected stale command does not speak a successful confirmation',
    () async {
      final commands = _Commands()..accept = false;
      final h = VoiceHarness(destinations: commands);
      addTearDown(h.container.dispose);
      context(h, suggestions(1));
      await h.start();
      await h.turn('option two');
      await h.finishReply();
      await h.turn('yes');
      expect(h.state.reply, contains('no longer available'));
      expect(h.state.reply, isNot(contains('Confirmed:')));
      await h.finishReply();
      expect(h.state.enabled, isTrue);
    },
  );

  test('unrelated journey questions still reach the reasoner', () async {
    final reasoner = QueueReasoner([
      const LocalReply(
        LocalIntent.clarify,
        'You saved a checklist for your SIM replacement.',
      ),
    ]);
    final h = VoiceHarness(reasoner: reasoner, destinations: _Commands());
    addTearDown(h.container.dispose);
    context(h, suggestions(1));
    await h.start();
    await h.turn('What did I need for my SIM replacement?');
    expect(reasoner.calls, 1);
    await h.finishReply();
  });

  test(
    'agreement after an intervening question cannot confirm an older address',
    () async {
      final commands = _Commands();
      final reasoner = QueueReasoner([
        const LocalReply(
          LocalIntent.clarify,
          'Would you like to review your checklist?',
        ),
      ]);
      final h = VoiceHarness(reasoner: reasoner, destinations: commands);
      addTearDown(h.container.dispose);
      context(h, suggestions(1));
      await h.start();
      await h.turn('option two');
      await h.finishReply();
      await h.turn('What did I need for my SIM replacement?');
      await h.finishReply();
      await h.turn('yes');
      expect(commands.confirmed, isEmpty);
      expect(h.state.reply, contains('Is that the place?'));
      await h.finishReply();
    },
  );
}

class _Commands implements DestinationSelectionCommands {
  final confirmed = <DestinationSelectionRequest>[];
  final rejected = <DestinationSelectionRequest>[];
  bool accept = true;
  @override
  bool confirm(DestinationSelectionRequest request) {
    confirmed.add(request);
    return accept;
  }

  @override
  bool reject(DestinationSelectionRequest request) {
    rejected.add(request);
    return accept;
  }
}
