/// Conservative rejection of clearly poor Whisper segments, not a calibrated
/// probability that a destination is correct. Place confirmation remains required.
enum TranscriptionQuality {
  usable,
  uncertain,
  noSpeech;

  static TranscriptionQuality evaluate(Map<dynamic, dynamic> response) {
    final segments = response['segments'];
    // Custom compatible endpoints may omit metadata. Preserve that contract.
    if (segments is! List || segments.isEmpty) return usable;
    var sawText = false;
    var allNoSpeech = true;
    for (final segment in segments) {
      if (segment is! Map || '${segment['text'] ?? ''}'.trim().isEmpty)
        continue;
      sawText = true;
      final logprob = segment['avg_logprob'];
      final noSpeechProb = segment['no_speech_prob'];
      final compression = segment['compression_ratio'];
      final noSpeechSegment =
          logprob is num &&
          logprob.isFinite &&
          noSpeechProb is num &&
          noSpeechProb.isFinite &&
          noSpeechProb > 0.6 &&
          logprob < -1.0;
      allNoSpeech = allNoSpeech && noSpeechSegment;
      // A doubtful word in a longer instruction must not silently disappear.
      if (!noSpeechSegment &&
          ((logprob is num && (!logprob.isFinite || logprob < -1.0)) ||
              (compression is num &&
                  (!compression.isFinite || compression > 2.4)))) {
        return uncertain;
      }
    }
    if (sawText && allNoSpeech) return noSpeech;
    // Mixed speech/noise segments are also unsuitable for trip mutations.
    if (segments.any(
      (s) =>
          s is Map &&
          s['avg_logprob'] is num &&
          (s['avg_logprob'] as num) < -1.0,
    ))
      return uncertain;
    return usable;
  }
}
