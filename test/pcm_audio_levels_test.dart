import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:navi/features/voice/data/pcm_audio_levels.dart';

void main() {
  test(
    'PCM16 level metering preserves odd chunk boundaries and reports clipping',
    () {
      final data = ByteData(32000);
      for (var i = 0; i < 16000; i++) {
        data.setInt16(i * 2, i == 0 ? -32768 : 16384, Endian.little);
      }
      final bytes = data.buffer.asUint8List();
      final meter = PcmAudioMeter();
      expect(meter.add(bytes.sublist(0, 3)), isEmpty);
      final reading = meter.add(bytes.sublist(3)).single;
      expect(reading.rmsDbfs, closeTo(-6.02, .01));
      expect(reading.peakDbfs, closeTo(0, .001));
      expect(reading.clippedSamples, 1);
      expect(reading.normalizedLevel, closeTo(1.0, .01));
      final silence = meter.add(Uint8List(32000)).single;
      expect(silence.rmsDbfs, closeTo(-120, .001));
      expect(silence.clippedSamples, 0);
      expect(silence.normalizedLevel, 0.0);
    },
  );

  test(
    'short real-time window emits normalized speech energy and resets cleanly',
    () {
      final meter = PcmAudioMeter(windowSamples: 800);
      final data = ByteData(1600);
      for (var i = 0; i < 800; i++) {
        data.setInt16(i * 2, 4096, Endian.little); // ~ -18.06 dBFS
      }
      final reading = meter.add(data.buffer.asUint8List()).single;
      expect(reading.rmsDbfs, closeTo(-18.06, .05));
      expect(reading.normalizedLevel, greaterThan(0.7));
      expect(reading.normalizedLevel, lessThan(0.8));

      // Partial odd byte is cleared by reset().
      expect(meter.add(Uint8List.fromList([0x7F])), isEmpty);
      meter.reset();
      expect(meter.add(Uint8List(1600)).single.normalizedLevel, 0.0);
    },
  );
}
