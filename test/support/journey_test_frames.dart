import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/voice/application/voice_session_controller.dart';
import 'package:navi/features/voice/domain/voice_types.dart';

import 'voice_harness.dart';

/// Advance the intro and router in frames, then settle the speech fixture.
/// pumpAndSettle alone cannot flush work scheduled in the real async zone.
Future<void> settleMapEntry(WidgetTester tester) async {
  final map = find.byKey(const ValueKey('journey-map-preview'));
  VoicePhase? phase;
  for (var frame = 0; frame < 24; frame++) {
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(flushVoice);
    if (map.evaluate().isEmpty) continue;
    phase = ProviderScope.containerOf(
      tester.element(map),
    ).read(voiceSessionProvider).phase;
    if (phase == VoicePhase.off) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Map entry did not settle: map=${map.evaluate().length}, voice=$phase');
}
