import 'dart:typed_data';

/// Encodes raw 16-bit little-endian mono PCM bytes into an in-memory RIFF/WAVE
/// container suitable for cloud STT endpoints, without writing temporary files.
Uint8List encodePcm16MonoWav(
  Uint8List pcmBytes, {
  int sampleRate = 16000,
}) {
  assert(sampleRate > 0);
  // Align to whole 16-bit samples.
  final dataLength = pcmBytes.length & ~1;
  final totalLength = 44 + dataLength;
  final buffer = Uint8List(totalLength);
  final header = ByteData.sublistView(buffer, 0, 44);

  // RIFF chunk descriptor ("RIFF", fileSize - 8, "WAVE")
  header.setUint32(0, 0x52494646, Endian.big); // "RIFF"
  header.setUint32(4, 36 + dataLength, Endian.little);
  header.setUint32(8, 0x57415645, Endian.big); // "WAVE"

  // "fmt " sub-chunk (16 bytes for PCM)
  header.setUint32(12, 0x666D7420, Endian.big); // "fmt "
  header.setUint32(16, 16, Endian.little); // Subchunk1Size = 16
  header.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
  header.setUint16(22, 1, Endian.little); // NumChannels = 1 (Mono)
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
  header.setUint16(32, 2, Endian.little); // BlockAlign
  header.setUint16(34, 16, Endian.little); // BitsPerSample = 16

  // "data" sub-chunk
  header.setUint32(36, 0x64617461, Endian.big); // "data"
  header.setUint32(40, dataLength, Endian.little);

  if (dataLength > 0) {
    buffer.setRange(44, 44 + dataLength, pcmBytes);
  }
  return buffer;
}

/// Applies clean software peak normalization to 16-bit mono PCM audio before
/// Whisper upload so softer voices or trailing words are boosted to an optimal
/// ~-3 dBFS target without clipping or over-amplifying room hiss.
Uint8List normalizePcm16Mono(Uint8List pcmBytes) {
  final length = pcmBytes.length & ~1;
  if (length < 4) return pcmBytes;
  final view = ByteData.sublistView(pcmBytes, 0, length);

  var maxAbs = 0;
  for (var offset = 0; offset < length; offset += 2) {
    final sample = view.getInt16(offset, Endian.little).abs();
    if (sample > maxAbs) maxAbs = sample;
  }
  // Ignore near-zero silence or audio already near full scale.
  if (maxAbs < 350 || maxAbs >= 20000) return pcmBytes;

  final gain = (23000.0 / maxAbs).clamp(1.0, 5.5);
  final out = Uint8List(length);
  final outView = ByteData.sublistView(out);
  for (var offset = 0; offset < length; offset += 2) {
    final sample = view.getInt16(offset, Endian.little);
    final boosted = (sample * gain).round().clamp(-32767, 32767);
    outView.setInt16(offset, boosted, Endian.little);
  }
  return out;
}

/// Normalizes a streaming RIFF/WAVE response (such as Groq Orpheus TTS, which
/// writes `0xFFFFFFFF` chunk sizes and embeds a `LIST` metadata chunk) into a
/// canonical 44-byte PCM16 mono WAV with exact byte lengths.
Uint8List? normalizeStreamingWav(Uint8List rawWav) {
  if (rawWav.length <= 44) return null;
  final view = ByteData.sublistView(rawWav);
  if (view.getUint32(0, Endian.big) != 0x52494646 || // "RIFF"
      view.getUint32(8, Endian.big) != 0x57415645) {
    // "WAVE"
    return null;
  }

  var sampleRate = 24000;
  var offset = 12;
  while (offset + 8 <= rawWav.length) {
    final chunkId = view.getUint32(offset, Endian.big);
    final chunkSize = view.getUint32(offset + 4, Endian.little);
    final dataStart = offset + 8;

    if (chunkId == 0x666D7420 && dataStart + 16 <= rawWav.length) {
      // "fmt "
      sampleRate = view.getUint32(dataStart + 4, Endian.little);
    } else if (chunkId == 0x64617461) {
      // "data"
      final pcmBytes = Uint8List.sublistView(rawWav, dataStart);
      if (pcmBytes.length < 2) return null;
      return encodePcm16MonoWav(
        pcmBytes,
        sampleRate: sampleRate > 0 ? sampleRate : 24000,
      );
    }

    if (chunkSize == 0xFFFFFFFF || dataStart + chunkSize > rawWav.length) {
      break;
    }
    offset = dataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }
  return null;
}

