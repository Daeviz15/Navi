import 'dart:math' as math;
import 'dart:typed_data';

class PcmAudioLevels {
  const PcmAudioLevels(this.rmsDbfs, this.peakDbfs, this.clippedSamples);
  final double rmsDbfs, peakDbfs;
  final int clippedSamples;

  /// Maps speech RMS from [-50 dBFS, -6 dBFS] into a perceptual [0.0, 1.0] range.
  double get normalizedLevel {
    const floorDbfs = -50.0;
    const ceilingDbfs = -6.0;
    if (rmsDbfs <= floorDbfs) return 0.0;
    if (rmsDbfs >= ceilingDbfs) return 1.0;
    return (rmsDbfs - floorDbfs) / (ceilingDbfs - floorDbfs);
  }
}

/// Streaming PCM16 level measurements. No recordings or text retained.
class PcmAudioMeter {
  PcmAudioMeter({this.windowSamples = 16000}) : assert(windowSamples > 0);

  final int windowSamples;
  int? _lowByte;
  int _count = 0, _squares = 0, _peak = 0, _clipped = 0;

  void reset() {
    _lowByte = null;
    _count = _squares = _peak = _clipped = 0;
  }

  List<PcmAudioLevels> add(Uint8List bytes) {
    final readings = <PcmAudioLevels>[];
    for (final byte in bytes) {
      if (_lowByte == null) {
        _lowByte = byte;
        continue;
      }
      final unsigned = _lowByte! | (byte << 8);
      final sample = unsigned >= 32768 ? unsigned - 65536 : unsigned;
      _lowByte = null;
      _count++;
      _squares += sample * sample;
      _peak = math.max(_peak, sample.abs());
      if (sample == -32768 || sample == 32767) _clipped++;
      if (_count == windowSamples) {
        final rms = math.sqrt(_squares / _count) / 32768;
        readings.add(
          PcmAudioLevels(
            20 * math.log(math.max(rms, .000001)) / math.ln10,
            20 * math.log(math.max(_peak / 32768, .000001)) / math.ln10,
            _clipped,
          ),
        );
        _count = _squares = _peak = _clipped = 0;
      }
    }
    return readings;
  }
}
