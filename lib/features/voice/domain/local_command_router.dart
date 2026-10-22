enum LocalIntent { greeting, destination, identity, gratitude, sleep, unsupported }

class LocalReply {
  const LocalReply(this.intent, this.text, {this.destination, this.followUp = true});
  final LocalIntent intent;
  final String text;
  final String? destination;
  final bool followUp;
}

/// Deliberately bounded commands. Location names still need real geocoding.
class LocalCommandRouter {
  const LocalCommandRouter();

  static final _wakePrefix = RegExp(
    r'^(?:(?:hey|hi|hello)\s+(?:navi|navy|navii|navie|navvy|nabby)|(?:hey|hi|hello))\b[\s,!.]*',
    caseSensitive: false,
  );

  String removeWakePhrase(String value) => value
      .trim()
      .replaceFirst(_wakePrefix, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  LocalReply route(String utterance) {
    final text = removeWakePhrase(utterance).replaceAll(RegExp(r'[.!?]+$'), '').trim();
    final normalized = text.toLowerCase().replaceAll('’', "'");
    if (normalized.isEmpty || RegExp(r'^(?:good morning|good afternoon|good evening)(?: navi)?$').hasMatch(normalized)) {
      return const LocalReply(LocalIntent.greeting, 'Hey! Where are we heading?');
    }
    if (RegExp(r'^(?:stop listening|go to sleep|goodbye|bye(?: navi)?)$').hasMatch(normalized)) {
      return const LocalReply(LocalIntent.sleep, 'Alright. I’m here when you need me.', followUp: false);
    }
    if (RegExp(r'^(?:thank you|thanks)(?: navi)?$').hasMatch(normalized)) {
      return const LocalReply(LocalIntent.gratitude, 'Anytime. Where to next?');
    }
    if (RegExp(r'^(?:who are you|what is your name|what\x27s your name)$').hasMatch(normalized)) {
      return const LocalReply(LocalIntent.identity, 'I’m Navi, your travel companion. Where would you like to go?');
    }
    final match = RegExp(
      r'^(?:please\s+)?(?:take me to|navigate to|directions to|let\x27s go to|i want to go to|i would like to go to|go to)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match != null) {
      final destination = match.group(1)!.trim();
      if (destination.length >= 2 && destination.length <= 120 && !destination.contains(RegExp(r'[\r\n]'))) {
        return LocalReply(LocalIntent.destination,
          'I heard $destination. I’ve put it in your destination field for you to check.',
          destination: destination, followUp: false);
      }
    }
    return const LocalReply(LocalIntent.unsupported,
      'I can greet you and help enter a destination for now. Try saying, take me to Lekki.');
  }
}
