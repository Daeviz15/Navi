import 'dart:math';

class CompanionIdlePolicy {
  CompanionIdlePolicy({
    this.minimumQuiet = const Duration(seconds: 90),
    this.maximumQuiet = const Duration(seconds: 150),
    this.gestureTimeout = const Duration(seconds: 12),
    Random? random,
    DateTime Function()? now,
  }) : assert(maximumQuiet >= minimumQuiet),
       _random = random ?? Random(),
       now = now ?? DateTime.now;

  final Duration minimumQuiet, maximumQuiet, gestureTimeout;
  final Random _random;
  final DateTime Function() now;

  Duration nextQuietInterval() =>
      minimumQuiet +
      Duration(
        milliseconds: _random.nextInt(
          (maximumQuiet - minimumQuiet).inMilliseconds + 1,
        ),
      );
}
