import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/character/domain/idle_clip_selector.dart';
import 'package:navi/features/character/domain/navi_clip.dart';
import 'package:navi/features/voice/domain/local_command_router.dart';

void main() {
  const router = LocalCommandRouter();
  test(
    'phonetic wake prefixes require detector evidence and preserve supported requests',
    () {
      expect(
        router
            .route('Y NAVY take me to London', wakeDetected: true)
            .destination,
        'London',
      );
      expect(
        router.route('Y NAVY take me to London').intent,
        LocalIntent.unsupported,
      );
      expect(
        router.route('Y TAKE ME TO LAGOS', wakeDetected: true).destination,
        'LAGOS',
      );
      expect(
        router
            .route('HE NABBE TAKE ME TO LONDON', wakeDetected: true)
            .destination,
        'LONDON',
      );
      expect(
        router.route('I love you', wakeDetected: true).intent,
        LocalIntent.acknowledgment,
      );
      expect(
        router
            .route("Hey Navi don't take me to London", wakeDetected: true)
            .destination,
        isNull,
      );
    },
  );
  test(
    'wake-only recognition variants greet; continuous requests preserve destinations',
    () {
      for (final greeting in [
        'Hey Navi',
        'HI NAVY',
        'HELLO NAVI!',
        'HEY NAVIG',
      ]) {
        expect(router.route(greeting).intent, LocalIntent.greeting);
      }
      expect(
        router.route('Hey Navi take me to Lekki Phase 1').destination,
        'Lekki Phase 1',
      );
      expect(
        router.route('Hi Navi I want to go to Lagos').destination,
        'Lagos',
      );
      expect(router.route('take me to').intent, LocalIntent.unsupported);
      expect(
        router.route('take me to ${'x' * 121}').intent,
        LocalIntent.unsupported,
      );
      expect(router.route('book a flight').intent, LocalIntent.unsupported);
    },
  );

  test('idle selection avoids repeats and respects the rare clip cooldown', () {
    var now = DateTime(2026);
    final selector = IdleClipSelector(random: Random(42), now: () => now);
    var previous = NaviClips.sip.id;
    DateTime? lastDaydream;
    var daydreams = 0;
    for (var i = 0; i < 200; i++) {
      final clip = selector.next(previous);
      expect(clip.id, isNot(previous));
      expect(NaviClips.idle, contains(clip));
      if (clip == NaviClips.daydream) {
        if (lastDaydream != null) {
          expect(
            now.difference(lastDaydream),
            greaterThanOrEqualTo(clip.cooldown),
          );
        }
        lastDaydream = now;
        daydreams++;
      }
      previous = clip.id;
      now = now.add(const Duration(seconds: 10));
    }
    expect(daydreams, greaterThan(0));
    expect(daydreams, lessThan(50));
  });
}
