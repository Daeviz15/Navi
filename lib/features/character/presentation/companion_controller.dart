import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice/application/voice_session_controller.dart';
import '../../voice/domain/voice_types.dart';
import '../domain/idle_clip_selector.dart';
import '../domain/navi_clip.dart';
import '../domain/companion_idle_policy.dart';

enum CompanionActivity { idle, reaction, listening, thinking, speaking }

class CompanionFrame {
  const CompanionFrame(
    this.activity,
    this.clip,
    this.revision, {
    this.still = false,
  });
  final CompanionActivity activity;
  final NaviClip clip;
  final int revision;
  final bool still;
  bool get repeat =>
      !still &&
      (activity == CompanionActivity.listening ||
          activity == CompanionActivity.thinking ||
          activity == CompanionActivity.speaking);
}

final companionIdlePolicyProvider = Provider<CompanionIdlePolicy>(
  (ref) => CompanionIdlePolicy(),
);

final companionProvider = NotifierProvider<CompanionController, CompanionFrame>(
  CompanionController.new,
);

/// Idle/touch behaviors yield immediately to the actual voice session state.
class CompanionController extends Notifier<CompanionFrame> {
  final _idle = IdleClipSelector();
  late CompanionIdlePolicy _policy;
  late VoicePhase _voicePhase;
  Timer? _quietTimer, _gestureDeadline;
  bool _visible = false, _reduceMotion = false, _disposed = false;
  final _visibleSurfaces = <String>{};
  String _previousIdle = NaviClips.sip.id;
  DateTime? _lastTap;

  @override
  CompanionFrame build() {
    _policy = ref.read(companionIdlePolicyProvider);
    _voicePhase = ref.read(voiceSessionProvider).phase;
    ref.onDispose(() {
      _disposed = true;
      _quietTimer?.cancel();
      _gestureDeadline?.cancel();
    });
    ref.listen(voiceSessionProvider.select((state) => state.phase), (_, phase) {
      _voicePhase = phase;
      _quietTimer?.cancel();
      _gestureDeadline?.cancel();
      final activity = _activity(phase);
      if (activity == state.activity &&
          (activity != CompanionActivity.idle || state.still)) {
        _scheduleIdle();
        return;
      }
      state = _frame(activity, state.revision + 1);
      _scheduleIdle();
    });
    return _frame(_activity(_voicePhase), 0);
  }

  CompanionFrame _frame(CompanionActivity activity, int revision) =>
      CompanionFrame(
        activity,
        _clip(activity),
        revision,
        still:
            activity == CompanionActivity.idle ||
            activity == CompanionActivity.listening,
      );

  bool get _canIdle =>
      _visible &&
      !_reduceMotion &&
      !_disposed &&
      _voicePhase == VoicePhase.off;

  void setVisible(bool visible) => setSurfaceVisible('home', visible);

  void setSurfaceVisible(String owner, bool visible) {
    if (_disposed) return;
    if (visible) {
      _visibleSurfaces.add(owner);
    } else {
      _visibleSurfaces.remove(owner);
    }
    final nowVisible = _visibleSurfaces.isNotEmpty;
    if (_visible == nowVisible) return;
    _visible = nowVisible;
    _quietTimer?.cancel();
    if (!_visible) {
      _gestureDeadline?.cancel();
      return;
    }
    if (state.activity == CompanionActivity.reaction ||
        (state.activity == CompanionActivity.idle && !state.still)) {
      _rest();
    } else {
      _scheduleIdle();
    }
  }

  void setReducedMotion(bool reduced) {
    if (_disposed || _reduceMotion == reduced) return;
    _reduceMotion = reduced;
    if (reduced &&
        (state.activity == CompanionActivity.reaction ||
            (state.activity == CompanionActivity.idle && !state.still))) {
      _rest();
    } else {
      _scheduleIdle();
    }
  }

  void userInteracted() {
    if (_disposed) return;
    if (state.activity == CompanionActivity.idle && !state.still) {
      _rest();
    } else {
      _scheduleIdle();
    }
  }

  void _scheduleIdle() {
    _quietTimer?.cancel();
    if (!_canIdle || state.activity != CompanionActivity.idle || !state.still) {
      return;
    }
    _quietTimer = Timer(_policy.nextQuietInterval(), () {
      if (!_canIdle ||
          state.activity != CompanionActivity.idle ||
          !state.still) {
        return;
      }
      final next = _idle.next(_previousIdle);
      _previousIdle = next.id;
      state = CompanionFrame(CompanionActivity.idle, next, state.revision + 1);
      _watchGesture();
    });
  }

  void _watchGesture() {
    _gestureDeadline?.cancel();
    final revision = state.revision;
    _gestureDeadline = Timer(_policy.gestureTimeout, () {
      if (!_disposed && state.revision == revision) _rest();
    });
  }

  void _rest() {
    _gestureDeadline?.cancel();
    state = _frame(CompanionActivity.idle, state.revision + 1);
    _scheduleIdle();
  }

  CompanionActivity _activity(VoicePhase phase) => switch (phase) {
    VoicePhase.listening => CompanionActivity.listening,
    VoicePhase.preparing ||
    VoicePhase.transcribing ||
    VoicePhase.preparingReply => CompanionActivity.thinking,
    VoicePhase.speaking => CompanionActivity.speaking,
    _ => CompanionActivity.idle,
  };

  NaviClip _clip(CompanionActivity activity) => switch (activity) {
    CompanionActivity.listening => NaviClips.listening,
    CompanionActivity.thinking => NaviClips.thinking,
    CompanionActivity.speaking => NaviClips.speaking,
    _ => NaviClips.sip,
  };

  void clipCompleted(int revision) {
    if (_disposed ||
        revision != state.revision ||
        state.repeat ||
        state.still) {
      return;
    }
    if (state.activity == CompanionActivity.idle ||
        state.activity == CompanionActivity.reaction) {
      _rest();
    }
  }

  void touched() {
    if (_disposed) return;
    if (state.activity != CompanionActivity.idle &&
        state.activity != CompanionActivity.reaction) {
      return;
    }
    _quietTimer?.cancel();
    if (_reduceMotion) {
      _rest();
      return;
    }
    final now = _policy.now();
    final elapsed = _lastTap == null
        ? const Duration(days: 1)
        : now.difference(_lastTap!);
    if (elapsed < const Duration(milliseconds: 250)) return;
    _lastTap = now;
    final clip = elapsed < const Duration(milliseconds: 1600)
        ? NaviClips.sideEye
        : NaviClips.smile;
    state = CompanionFrame(
      CompanionActivity.reaction,
      clip,
      state.revision + 1,
    );
    _watchGesture();
  }
}
