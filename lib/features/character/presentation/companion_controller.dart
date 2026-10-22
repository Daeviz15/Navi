import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../voice/application/voice_session_controller.dart';
import '../../voice/domain/voice_types.dart';
import '../domain/idle_clip_selector.dart';
import '../domain/navi_clip.dart';

enum CompanionActivity { idle, reaction, listening, thinking, speaking }

class CompanionFrame {
  const CompanionFrame(this.activity, this.clip, this.revision);
  final CompanionActivity activity;
  final NaviClip clip;
  final int revision;
  bool get repeat => activity == CompanionActivity.listening ||
      activity == CompanionActivity.thinking || activity == CompanionActivity.speaking;
}

final companionProvider = NotifierProvider<CompanionController, CompanionFrame>(CompanionController.new);

/// Idle/touch behaviors yield immediately to the actual voice session state.
class CompanionController extends Notifier<CompanionFrame> {
  final _idle = IdleClipSelector();
  DateTime? _lastTap;

  @override
  CompanionFrame build() {
    ref.listen(voiceSessionProvider.select((state) => state.phase), (_, phase) {
      final activity = switch (phase) {
        VoicePhase.listening => CompanionActivity.listening,
        VoicePhase.preparing || VoicePhase.preparingReply => CompanionActivity.thinking,
        VoicePhase.speaking => CompanionActivity.speaking,
        _ => CompanionActivity.idle,
      };
      if (activity == state.activity) return;
      final clip = switch (activity) {
        CompanionActivity.listening => NaviClips.listening,
        CompanionActivity.thinking => NaviClips.thinking,
        CompanionActivity.speaking => NaviClips.speaking,
        _ => NaviClips.sip,
      };
      state = CompanionFrame(activity, clip, state.revision + 1);
    });
    return const CompanionFrame(CompanionActivity.idle, NaviClips.sip, 0);
  }

  void clipCompleted(int revision) {
    if (revision != state.revision || state.repeat) return;
    final next = _idle.next(state.clip.id);
    state = CompanionFrame(CompanionActivity.idle, next, state.revision + 1);
  }

  void touched() {
    if (state.activity != CompanionActivity.idle && state.activity != CompanionActivity.reaction) return;
    final now = DateTime.now();
    final elapsed = _lastTap == null ? const Duration(days: 1) : now.difference(_lastTap!);
    if (elapsed < const Duration(milliseconds: 250)) return;
    _lastTap = now;
    final clip = elapsed < const Duration(milliseconds: 1600) ? NaviClips.sideEye : NaviClips.smile;
    state = CompanionFrame(CompanionActivity.reaction, clip, state.revision + 1);
  }
}
