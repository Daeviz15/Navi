import 'dart:math';

import 'navi_clip.dart';

class IdleClipSelector {
  IdleClipSelector({Random? random, DateTime Function()? now})
      : _random = random ?? Random(), _now = now ?? DateTime.now;
  final Random _random;
  final DateTime Function() _now;
  final _lastPlayed = <String, DateTime>{};

  NaviClip next(String previous) {
    final now = _now();
    var candidates = NaviClips.idle.where((clip) => clip.id != previous &&
      (!_lastPlayed.containsKey(clip.id) || now.difference(_lastPlayed[clip.id]!) >= clip.cooldown)).toList();
    if (candidates.isEmpty) candidates = NaviClips.idle.where((clip) => clip.id != previous).toList();
    var draw = _random.nextInt(candidates.fold<int>(0, (total, clip) => total + clip.weight));
    for (final clip in candidates) {
      draw -= clip.weight;
      if (draw < 0) {
        _lastPlayed[clip.id] = now;
        return clip;
      }
    }
    return candidates.last;
  }
}
