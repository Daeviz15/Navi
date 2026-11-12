import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/navi_companion.dart';
import '../../character/presentation/companion_controller.dart';
import '../../voice/application/voice_session_controller.dart';
import '../../voice/domain/voice_types.dart';

class JourneyCompanionPanel extends ConsumerStatefulWidget {
  const JourneyCompanionPanel({super.key});

  @override
  ConsumerState<JourneyCompanionPanel> createState() =>
      _JourneyCompanionPanelState();
}

class _JourneyCompanionPanelState extends ConsumerState<JourneyCompanionPanel>
    with WidgetsBindingObserver {
  late final VoiceSessionController _voice;
  late final CompanionController _companion;

  @override
  void initState() {
    super.initState();
    _voice = ref.read(voiceSessionProvider.notifier);
    _companion = ref.read(companionProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _voice.setSurfaceVisible('journey', true);
      _companion.setSurfaceVisible('journey', true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _companion.setReducedMotion(reduced);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _voice.setForeground(
      state == AppLifecycleState.resumed,
      releaseModels: state != AppLifecycleState.inactive,
    );
    _companion.setSurfaceVisible('journey', state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.setSurfaceVisible('journey', false);
    _companion.setSurfaceVisible('journey', false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceSessionProvider);
    final frame = ref.watch(companionProvider);
    final level = ref.watch(voiceAudioLevelProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('journey-companion'),
      children: [
        NaviCompanion(
          size: 144,
          clip: frame.clip,
          activity: frame.activity,
          revision: frame.revision,
          holdPose: frame.still,
          repeat: frame.repeat,
          audioLevel: level,
          engaged: voice.enabled,
          onCompleted: () => _companion.clipCompleted(frame.revision),
          onTap: () => unawaited(_voice.togglePushToTalk()),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                voice.enabled
                    ? voice.caption
                    : voice.reply.isNotEmpty
                    ? voice.reply
                    : 'I’m right here. Tap to talk.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: voice.enabled ? 'Stop talking to Navi' : 'Talk to Navi',
              onPressed: _voice.togglePushToTalk,
              icon: Icon(
                voice.phase == VoicePhase.listening
                    ? Icons.mic_rounded
                    : Icons.mic_none_rounded,
                size: 20,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
