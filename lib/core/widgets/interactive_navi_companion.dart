import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/character/presentation/companion_controller.dart';
import '../../features/journey/presentation/journey_controller.dart';
import '../../features/voice/application/voice_session_controller.dart';
import 'navi_companion.dart';

/// The single conversation control, shared by every screen displaying Navi.
class InteractiveNaviCompanion extends ConsumerWidget {
  const InteractiveNaviCompanion({
    super.key,
    required this.size,
    this.controlKey = const ValueKey('navi-conversation-control'),
  });
  final double size;
  final Key controlKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceSessionProvider);
    final frame = ref.watch(companionProvider);
    final level = ref.watch(voiceAudioLevelProvider);
    void activate() {
      ref.read(companionProvider.notifier).userInteracted();
      unawaited(
        ref
            .read(voiceSessionProvider.notifier)
            .toggleConversation(
              destination: ref.read(journeyDraftProvider).destination,
            ),
      );
    }

    return Semantics(
      key: controlKey,
      button: true,
      label: 'Navi',
      hint: voice.enabled ? 'Tap to stop talking' : 'Tap to talk',
      onTap: activate,
      child: ExcludeSemantics(
        child: NaviCompanion(
          size: size,
          clip: frame.clip,
          activity: frame.activity,
          revision: frame.revision,
          repeat: frame.repeat,
          holdPose: frame.still,
          audioLevel: level,
          engaged: voice.enabled,
          onCompleted: () => ref
              .read(companionProvider.notifier)
              .clipCompleted(frame.revision),
          onTap: activate,
        ),
      ),
    );
  }
}
