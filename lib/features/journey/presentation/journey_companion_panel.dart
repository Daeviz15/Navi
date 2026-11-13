import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/interactive_navi_companion.dart';
import '../../character/presentation/companion_controller.dart';
import '../../voice/application/voice_session_controller.dart';

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
      transient: state == AppLifecycleState.inactive,
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('journey-companion'),
      children: [
        const InteractiveNaviCompanion(size: 144),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            voice.caption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (voice.transcript.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'You: ${voice.transcript}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}
