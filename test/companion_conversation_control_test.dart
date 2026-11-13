import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/home/presentation/home_screen.dart';
import 'package:navi/features/journey/presentation/journey_companion_panel.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

import 'support/voice_harness.dart';

void main() {
  for (final screen in ['home', 'journey']) {
    testWidgets('$screen exposes Navi as the only voice control', (
      tester,
    ) async {
      final h = VoiceHarness();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            home: screen == 'home'
                ? const HomeScreen()
                : const Scaffold(body: JourneyCompanionPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.microphones, isEmpty);
      for (final icon in [
        Icons.hearing_rounded,
        Icons.hearing_outlined,
        Icons.mic_rounded,
        Icons.mic_none_rounded,
      ]) {
        expect(find.byIcon(icon), findsNothing);
      }
      final navi = find.byKey(const ValueKey('navi-conversation-control'));
      expect(navi, findsOneWidget);
      expect(
        tester.getSemantics(navi),
        matchesSemantics(
          label: 'Navi',
          hint: 'Tap to talk',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(navi);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(h.state.phase, VoicePhase.listening);
      expect(h.microphone.running, isTrue);
      expect(
        tester.getSemantics(navi),
        matchesSemantics(
          label: 'Navi',
          hint: 'Tap to stop talking',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(navi);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(h.state.enabled, isFalse);
      expect(h.microphone.running, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      h.container.dispose();
      await tester.pump();
      semantics.dispose();
    });
  }
}
