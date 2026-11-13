import 'voice_gateway.dart';

enum LocalIntent {
  greeting,
  destination,
  purpose,
  clarify,
  identity,
  gratitude,
  sleep,
  unsupported,
  acknowledgment,
}

class LocalReply {
  const LocalReply(
    this.intent,
    this.text, {
    this.destination,
    this.purposeSummary,
    this.isCasual = false,
    this.checklist = const <String>[],
    this.followUp = true,
    this.changeTrip = false,
    this.endTrip = false,
  });
  final LocalIntent intent;
  final String text;
  final String? destination;
  final String? purposeSummary;
  final bool isCasual;
  final List<String> checklist;
  final bool followUp;
  final bool changeTrip;
  final bool endTrip;
}

/// Deliberately bounded commands. Location names still need real geocoding.
class LocalCommandRouter implements VoiceReasoner {
  const LocalCommandRouter();

  @override
  Future<LocalReply> resolve(
    String utterance, {
    required bool wakeDetected,
  }) async => route(utterance, wakeDetected: wakeDetected);

  static final _wakePrefix = RegExp(
    r'^(?:(?:hey|hi|hello)[\s,!.:]+(?:navi|navy|navii|navie|navvy|nabby|navig)|(?:hey|hi|hello))\b[\s,!.:]*',
    caseSensitive: false,
  );

  static final _detectedWakePrefix = RegExp(
    r'^(?:(?:hey|hi|hello|hai)[\s,!.:]*(?:navi|navy|navii|navie|navvy|na vee)|(?:hay|high|y|aye|a|he|h)[\s,!.:]+(?:navi|navy|navii|navie|navvy|nabby|nabbe|navig|na vee))\b[\s,!.:]*',
    caseSensitive: false,
  );

  // A confirmed wake can be partly omitted by ASR. Remove only a known short
  // greeting fragment directly before a supported command; never negations.
  static final _wakeFragment = RegExp(
    r'^(?:hey|hi|hello|hay|high|y|aye|he|h)\s+(?=(?:please\s+)?(?:take me to|navigate to|directions to|i want to go to|i would like to go to|go to|who are you|stop listening)\b)',
    caseSensitive: false,
  );

  String removeWakePhrase(String value, {bool wakeDetected = false}) => value
      .trim()
      .replaceFirst(wakeDetected ? _detectedWakePrefix : _wakePrefix, '')
      .replaceFirst(wakeDetected ? _wakeFragment : RegExp(r'(?!)'), '')
      .replaceFirst(_wakePrefix, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  LocalReply route(String utterance, {bool wakeDetected = false}) {
    final text = removeWakePhrase(
      utterance,
      wakeDetected: wakeDetected,
    ).replaceAll(RegExp(r'[.!?]+$'), '').trim();
    final normalized = text.toLowerCase().replaceAll('’', "'");
    if (normalized.isEmpty ||
        RegExp(
          r'^(?:good morning|good afternoon|good evening)(?: navi)?$',
        ).hasMatch(normalized)) {
      return const LocalReply(
        LocalIntent.greeting,
        'Hey! Where are we heading?',
      );
    }
    if (RegExp(
      r'^(?:stop listening|go to sleep|goodbye|bye(?: navi)?)$',
    ).hasMatch(normalized)) {
      return const LocalReply(
        LocalIntent.sleep,
        'Alright. I’m here when you need me.',
        followUp: false,
      );
    }
    if (RegExp(r'^(?:thank you|thanks)(?: navi)?$').hasMatch(normalized)) {
      return const LocalReply(LocalIntent.gratitude, 'Anytime. Where to next?');
    }
    if (RegExp(
      r'^(?:who are you|what is your name|what\x27s your name)$',
    ).hasMatch(normalized)) {
      return const LocalReply(
        LocalIntent.identity,
        'I’m Navi, your travel companion. Where would you like to go?',
      );
    }
    final match = RegExp(
      r'^(?:please\s+)?(?:take me to|navigate to|directions to|let\x27s go to|i want to go to|i would like to go to|go to)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final destination = match.group(1)!.trim();
      if (destination.length >= 2 &&
          destination.length <= 120 &&
          !destination.contains(RegExp(r'[\r\n]'))) {
        return LocalReply(
          LocalIntent.destination,
          'I heard $destination. I’ve put it in your destination field for you to check.',
          destination: destination,
          followUp: false,
        );
      }
    }
    if (wakeDetected) {
      // The wake detector is authoritative about being called. A separate
      // uncertain transcript must not turn that greeting into a rejection.
      return const LocalReply(
        LocalIntent.acknowledgment,
        "Hey, I'm listening. Where would you like to go?",
      );
    }
    return const LocalReply(
      LocalIntent.unsupported,
      'I can greet you and help enter a destination for now. Try saying, take me to Lekki.',
    );
  }
}
