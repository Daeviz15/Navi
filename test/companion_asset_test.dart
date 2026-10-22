import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi/core/widgets/navi_companion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'light-mode animation loops with transparent background and opaque character',
    () async {
      final asset = await rootBundle.load(
        NaviCompanion.transparentAnimationAsset,
      );
      final codec = await ui.instantiateImageCodec(asset.buffer.asUint8List());
      addTearDown(codec.dispose);
      expect(codec.frameCount, 240);
      expect(codec.repetitionCount, -1);
      final frame = await codec.getNextFrame();
      addTearDown(frame.image.dispose);
      expect(frame.image.width, 540);
      expect(frame.image.height, 960);
      final pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final last = (frame.image.width * frame.image.height - 1) * 4;
      expect(pixels.getUint8(3), 0);
      expect(pixels.getUint8(last + 3), 0);
      final center = (480 * frame.image.width + 270) * 4;
      expect(pixels.getUint8(center + 3), 255);

      // Dark facial details must survive matting instead of becoming holes.
      var opaqueDarkPixels = 0;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        if (pixels.getUint8(i + 3) == 255 &&
            pixels.getUint8(i) < 24 &&
            pixels.getUint8(i + 1) < 24 &&
            pixels.getUint8(i + 2) < 24) {
          opaqueDarkPixels++;
        }
      }
      expect(opaqueDarkPixels, greaterThan(100));
    },
  );
}
