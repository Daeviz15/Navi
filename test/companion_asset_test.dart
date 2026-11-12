import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/character/domain/idle_clip_selector.dart';
import 'package:navi/features/character/domain/navi_clip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every selectable companion behavior has a unique id, positive weight and accessibility label',
    () {
      final ids = <String>{};
      for (final clip in NaviClips.all) {
        expect(ids.add(clip.id), isTrue, reason: 'Duplicate id: ${clip.id}');
        expect(clip.description.trim(), isNotEmpty, reason: clip.id);
        expect(clip.weight, greaterThan(0), reason: clip.id);
        expect(clip.cooldown.isNegative, isFalse, reason: clip.id);
      }
      expect(NaviClips.idle, isNotEmpty);
      for (final idle in NaviClips.idle) {
        expect(NaviClips.all, contains(idle));
      }
    },
  );

  test(
    'idle selector avoids immediate repeats and respects clip cooldowns',
    () {
      var clock = DateTime.utc(2026, 11, 11, 12);
      final selector = IdleClipSelector(
        random: Random(7),
        now: () => clock,
      );
      var previous = NaviClips.sip.id;
      for (var i = 0; i < 25; i++) {
        final next = selector.next(previous);
        expect(next.id, isNot(previous));
        if (next == NaviClips.daydream) {
          // Within the 35s cooldown, daydream cannot be picked again.
          clock = clock.add(const Duration(seconds: 10));
          final afterDaydream = selector.next(next.id);
          expect(afterDaydream, isNot(NaviClips.daydream));
          previous = afterDaydream.id;
        } else {
          clock = clock.add(const Duration(seconds: 40));
          previous = next.id;
        }
      }
    },
  );

  test('offline Syne font asset remains bundled and non-empty', () async {
    final font = await rootBundle.load('assets/fonts/Syne-Variable.ttf');
    expect(font.lengthInBytes, greaterThan(10000));
  });
}
