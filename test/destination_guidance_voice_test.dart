import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/journey/domain/journey_identity.dart';
import 'package:navi/features/navigation/domain/destination_selection.dart';
import 'package:navi/features/navigation/domain/navigation_gateway.dart';
import 'package:navi/features/voice/domain/voice_gateway.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

import 'support/voice_harness.dart';

const _identity = JourneyIdentity(tripId: 4);
const _place = DestinationPlace(
  id: 'ikeja',
  name: 'MTN',
  address: 'Allen Avenue, Ikeja, Lagos',
  point: GeoPoint(6.6, 3.35),
);

DestinationSuggestions _matches(int revision) => DestinationSuggestions(
  token: DestinationSearchToken(_identity, revision),
  places: const [_place],
);

Future<void> _prepare(VoiceHarness h, DestinationSuggestions matches) async {
  h.controller.updateTransitContext(
    JourneyTransitContext(
      identity: _identity,
      isActive: true,
      destination: 'MTN',
      destinationSuggestions: matches,
    ),
  );
  h.controller.setSurfaceVisible('journey', true);
  await flushVoice();
}

void main() {
  test(
    'changing travel mode does not repeat the same destination introduction',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      final matches = _matches(1);
      await _prepare(h, matches);
      final done = h.controller.announceMapEntry(_identity);
      await flushVoice();
      h.output.finish();
      await done;
      final next = _identity.nextIntent();
      h.controller.updateTransitContext(
        JourneyTransitContext(
          identity: next,
          isActive: true,
          destination: 'MTN',
        ),
      );
      await h.controller.announceMapEntry(next);
      expect(h.outputs, hasLength(1));
      expect(h.microphones, isEmpty);
    },
  );
  test(
    'map entry speaks while search is pending and survives arriving matches',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      h.controller.updateTransitContext(
        const JourneyTransitContext(
          identity: _identity,
          isActive: true,
          destination: 'MTN',
        ),
      );
      h.controller.setSurfaceVisible('journey', true);
      await flushVoice();
      final done = h.controller.announceMapEntry(_identity);
      await flushVoice();
      expect(h.output.messages, hasLength(1));
      final output = h.output;
      final matches = _matches(1);
      await _prepare(h, matches);
      expect(output.disposed, isFalse);
      expect(h.microphones, isEmpty);
      output.finish();
      await done;
      await h.controller.announceDestinationChoices(matches.token);
      expect(h.outputs, hasLength(1));
    },
  );
  test(
    'completed orientation is cleared when the address becomes confirmed',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      final matches = _matches(1);
      await _prepare(h, matches);
      final done = h.controller.announceDestinationChoices(matches.token);
      await flushVoice();
      h.output.finish();
      await done;
      expect(h.state.reply, isNotEmpty);
      h.controller.updateTransitContext(
        JourneyTransitContext(
          identity: _identity,
          isActive: true,
          destination: 'MTN',
          destinationSuggestions: matches,
          confirmedPlaceName: _place.name,
          confirmedAddress: _place.address,
        ),
      );
      expect(h.state.caption, 'Tap Navi to talk.');
      expect(h.state.enabled, isFalse);
      expect(h.microphones, isEmpty);
    },
  );

  test(
    'orientation speaks once per intent and never creates capture resources',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      final matches = _matches(1);
      await _prepare(h, matches);
      final done = h.controller.announceDestinationChoices(matches.token);
      await flushVoice();
      expect(h.state.enabled, isFalse);
      expect(h.microphones, isEmpty);
      expect(h.speeches, isEmpty);
      expect(h.output.messages.single, contains('Choose an address below'));
      h.output.started();
      expect(h.state.phase, VoicePhase.speaking);
      h.output.finish();
      await done;
      expect(h.state.phase, VoicePhase.off);
      expect(h.output.disposed, isTrue);
      await h.controller.announceDestinationChoices(matches.token);
      final replacement = _matches(2);
      await _prepare(h, replacement);
      await h.controller.announceDestinationChoices(replacement.token);
      expect(h.outputs, hasLength(1));
      expect(h.microphones, isEmpty);
    },
  );

  test('tapping Navi cancels orientation before starting capture', () async {
    final h = VoiceHarness();
    addTearDown(h.container.dispose);
    final matches = _matches(1);
    await _prepare(h, matches);
    final done = h.controller.announceDestinationChoices(matches.token);
    await flushVoice();
    final guidance = h.output;
    await h.controller.toggleConversation();
    await done;
    expect(guidance.disposed, isTrue);
    expect(h.state.enabled, isTrue);
    expect(h.state.phase, VoicePhase.listening);
    expect(h.microphone.starts, 1);
    expect(h.outputs, hasLength(2));
    await h.controller.toggleConversation();
    expect(h.state.phase, VoicePhase.off);
  });

  test(
    'guidance never interrupts a conversation or plays a stale search',
    () async {
      final h = VoiceHarness();
      addTearDown(h.container.dispose);
      final matches = _matches(1);
      await _prepare(h, matches);
      await h.controller.toggleConversation();
      await h.controller.announceDestinationChoices(matches.token);
      expect(h.state.phase, VoicePhase.listening);
      expect(h.outputs, hasLength(1));
      expect(h.output.messages, isEmpty);
      await h.controller.toggleConversation();
      await _prepare(h, _matches(2));
      await h.controller.announceDestinationChoices(matches.token);
      expect(h.outputs, hasLength(1));
    },
  );

  test(
    'confirmed address cancels pending synthesis and cannot start late playback',
    () async {
      final gate = Completer<void>();
      final h = VoiceHarness(outputGate: gate);
      addTearDown(h.container.dispose);
      final matches = _matches(1);
      await _prepare(h, matches);
      final done = h.controller.announceDestinationChoices(matches.token);
      await flushVoice();
      final guidance = h.output;
      h.controller.updateTransitContext(
        JourneyTransitContext(
          identity: _identity,
          isActive: true,
          destination: 'MTN',
          confirmedPlaceName: _place.name,
          confirmedAddress: _place.address,
          destinationSuggestions: matches,
        ),
      );
      gate.complete();
      await done;
      expect(guidance.messages, isEmpty);
      expect(guidance.disposed, isTrue);
      expect(h.state.phase, VoicePhase.off);
      expect(h.microphones, isEmpty);
    },
  );

  test(
    'leaving map or backgrounding cancels guidance even if Home is retained',
    () async {
      for (final background in [false, true]) {
        final h = VoiceHarness();
        final matches = _matches(1);
        await _prepare(h, matches);
        h.controller.setHomeVisible(true);
        final done = h.controller.announceDestinationChoices(matches.token);
        await flushVoice();
        final output = h.output;
        if (background) {
          h.controller.setForeground(false);
        } else {
          h.controller.setSurfaceVisible('journey', false);
        }
        await done;
        await flushVoice();
        expect(output.disposed, isTrue);
        expect(h.state.enabled, isFalse);
        expect(h.state.phase, VoicePhase.off);
        expect(h.microphones, isEmpty);
        h.container.dispose();
      }
    },
  );
}
