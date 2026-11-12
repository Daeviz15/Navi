import 'voice_types.dart';

/// A greeting must start the utterance and name Navi. No fuzzy substring wakes.
/// Two agreeing partials, or one final result, accept the greeting.
class StreamingGreetingPolicy {
  static const endpointGrace = Duration(milliseconds: 650);
  static final _greeting = RegExp(
    r'^\s*(hey|hi|hello|hai)[\s,!.:]*(navi|navy|navii|navie|navvy|na\s+vee)\b',
    caseSensitive: false,
  );

  SpeechMode _mode = SpeechMode.muted;
  String? _line, _candidate;
  final _completed = <String>{};
  final _parts = <String, String>{};
  Duration? _endAfter;
  int _agreements = 0;

  SpeechMode get mode => _mode;

  void reset(SpeechMode mode) {
    _mode = mode;
    _line = _candidate = null;
    _completed.clear();
    _parts.clear();
    _endAfter = null;
    _agreements = 0;
  }

  List<SpeechEvent> accept({
    required String line,
    required String text,
    required bool complete,
    Duration audioPosition = Duration.zero,
  }) {
    if (_mode == SpeechMode.muted || _completed.contains(line)) return const [];
    if (_line != line) {
      _line = line;
      _candidate = null;
      _agreements = 0;
    }
    final events = <SpeechEvent>[];
    if (_mode == SpeechMode.wake) {
      final match = _greeting.firstMatch(text);
      if (match == null) {
        _candidate = null;
        _agreements = 0;
        if (complete) _rememberCompleted(line);
        return events;
      }
      final recognized = match.group(1)!.toLowerCase();
      // A measured NAH-vee fixture is transcribed as the fused word Hainavi.
      // Keep the alias explicit and bounded; do not use edit-distance matching.
      final candidate = recognized == 'hai' ? 'hi' : recognized;
      _agreements = candidate == _candidate ? _agreements + 1 : 1;
      _candidate = candidate;
      if (!complete && _agreements < 2) return events;
      _mode = SpeechMode.listening;
      events.add(WakeDetected('${candidate.toUpperCase()}_NAVI'));
    }
    _parts[line] = text.trim();
    events.add(TranscriptChanged(_text));
    if (complete) {
      _rememberCompleted(line);
      _endAfter = audioPosition + endpointGrace;
    } else {
      _endAfter = null;
    }
    return events;
  }

  String get _text => _parts.values.where((part) => part.isNotEmpty).join(' ');

  void _rememberCompleted(String line) {
    _completed.add(line);
    if (_completed.length > 32) _completed.remove(_completed.first);
  }

  /// Advance only after a fresh native VAD/transcription pass. Wall-clock timers
  /// could expire while captured command audio is still waiting for inference.
  List<SpeechEvent> advance({
    required Duration audioPosition,
    required bool quiet,
  }) {
    if (_mode != SpeechMode.listening ||
        !quiet ||
        _endAfter == null ||
        audioPosition < _endAfter!) {
      return const [];
    }
    _mode = SpeechMode.muted;
    return [UtteranceEnded(_text)];
  }
}
