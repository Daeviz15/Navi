import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/route_progress.dart';

class NavigationReliabilityPolicy {
  const NavigationReliabilityPolicy({
    this.progress = const RouteProgressPolicy(),
    this.refreshCooldown = const Duration(seconds: 30),
    this.maxFailureBackoff = const Duration(minutes: 2),
  });
  final RouteProgressPolicy progress;
  final Duration refreshCooldown, maxFailureBackoff;
  Duration delayAfterFailure(int failures) {
    var delay = refreshCooldown;
    for (var i = 1; i < failures && delay < maxFailureBackoff; i++) {
      delay *= 2;
    }
    return delay > maxFailureBackoff ? maxFailureBackoff : delay;
  }
}

final navigationReliabilityPolicyProvider =
    Provider<NavigationReliabilityPolicy>(
      (ref) => const NavigationReliabilityPolicy(),
    );
