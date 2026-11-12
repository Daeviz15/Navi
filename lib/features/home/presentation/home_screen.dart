import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/widgets/navi_companion.dart';
import '../../journey/presentation/journey_controller.dart';
import '../../character/presentation/companion_controller.dart';
import '../../voice/application/voice_session_controller.dart';
import '../../voice/domain/voice_types.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _destination = TextEditingController();
  final _destinationFocus = FocusNode();
  late VoiceSessionController _voice;
  late CompanionController _companion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = ref.read(voiceSessionProvider.notifier);
    _companion = ref.read(companionProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _voice.setHomeVisible(true);
        _companion.setVisible(true);
      }
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
    _companion.setVisible(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.setHomeVisible(false);
    _companion.setVisible(false);
    _destination.dispose();
    _destinationFocus.dispose();
    super.dispose();
  }

  void _continue() {
    final destination = _destination.text.trim();
    if (destination.isEmpty) {
      _destinationFocus.requestFocus();
      _showMessage('Enter a destination to continue.');
      return;
    }
    ref.read(journeyDraftProvider.notifier).setDestination(destination);
    _destinationFocus.unfocus();
    _voice.suspendForNavigation();
    context.go('/initialize');
  }

  Future<void> _toggleHandsFree() => _voice.togglePushToTalk();

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _choosePlace(String place) {
    _destination.value = TextEditingValue(
      text: place,
      selection: TextSelection.collapsed(offset: place.length),
    );
    _destinationFocus.requestFocus();
  }

  void _showPlaces() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A few places to start',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final place in [
                'Lekki Phase 1',
                'MTN office, Ikeja',
                'Ologolo bus stop',
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    place,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  trailing: const Icon(Icons.north_west_rounded, size: 16),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _choosePlace(place);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final light = theme.brightness == Brightness.light;
    final voice = ref.watch(voiceSessionProvider);
    final audioLevel = ref.watch(voiceAudioLevelProvider);
    final companion = ref.watch(companionProvider);
    final draft = ref.watch(journeyDraftProvider);
    ref.listen(voiceSessionProvider, (previous, next) {
      if (next.destination != null &&
          next.destinationRevision != previous?.destinationRevision) {
        _destination.text = next.destination!;
        ref.read(journeyDraftProvider.notifier).setDestination(next.destination!);
      }
      if (next.checklistRevision != previous?.checklistRevision) {
        ref.read(journeyDraftProvider.notifier).setCompanionPrep(
          destination: next.destination,
          purposeSummary: next.purposeSummary,
          isCasual: next.isCasual,
          checklist: next.checklist,
        );
      }
    });

    return Listener(
      onPointerDown: (_) => _companion.userInteracted(),
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.near_me_rounded,
                        size: 18,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'navi',
                          textScaler: TextScaler.noScaling,
                          maxLines: 1,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.4,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '.',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: scheme.secondary,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: voice.phase == VoicePhase.error
                          ? 'Retry hands-free'
                          : voice.enabled
                          ? 'Turn off hands-free'
                          : 'Enable hands-free',
                      onPressed: _toggleHandsFree,
                      icon: Icon(
                        voice.enabled
                            ? Icons.hearing_rounded
                            : Icons.hearing_outlined,
                        size: 18,
                        color: voice.enabled
                            ? scheme.secondary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: light
                          ? 'Switch to dark mode'
                          : 'Switch to light mode',
                      onPressed: () => ref
                          .read(themeModeProvider.notifier)
                          .setLightMode(!light),
                      style: IconButton.styleFrom(
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      icon: Icon(
                        light
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        size: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final stageSize = math
                  .min(constraints.maxWidth - 56, compact ? 238.0 : 290.0)
                  .clamp(140.0, 290.0);
              return NotificationListener<UserScrollNotification>(
                onNotification: (_) {
                  _companion.userInteracted();
                  return false;
                },
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: compact ? 13 : 26),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: scheme.secondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'A LITTLE COMPANY. A BETTER JOURNEY.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 8,
                                      letterSpacing: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 13),
                            Text.rich(
                              TextSpan(
                                text: 'Where are we\n',
                                children: [
                                  TextSpan(
                                    text: 'off to today?',
                                    style: TextStyle(color: scheme.secondary),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.displaySmall,
                            ),
                            const SizedBox(height: 7),
                            Text(
                              "Your plans. My company. Let's find a way.",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                            SizedBox(height: compact ? 14 : 22),
                            Center(
                              child: NaviCompanion(
                                size: stageSize,
                                clip: companion.clip,
                                activity: companion.activity,
                                revision: companion.revision,
                                repeat: companion.repeat,
                                holdPose: companion.still,
                                audioLevel: audioLevel,
                                engaged:
                                    companion.activity ==
                                        CompanionActivity.listening ||
                                    companion.activity ==
                                        CompanionActivity.thinking ||
                                    companion.activity ==
                                        CompanionActivity.speaking,
                                onCompleted: () => ref
                                    .read(companionProvider.notifier)
                                    .clipCompleted(companion.revision),
                                onTap: () {
                                  ref
                                      .read(companionProvider.notifier)
                                      .touched();
                                  unawaited(_toggleHandsFree());
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (voice.transcript.isNotEmpty &&
                                voice.caption != voice.transcript) ...[
                              Center(
                                child: Container(
                                  key: const ValueKey('voice-user-transcript'),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surface,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  child: Text(
                                    '“${voice.transcript}”',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10.5,
                                      fontStyle: FontStyle.italic,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: scheme.secondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    voice.caption,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 22 : 30),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                border: Border.all(
                                  color: scheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.trip_origin_rounded,
                                        size: 12,
                                        color: scheme.secondary,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'YOUR NEXT STOP',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              letterSpacing: 1.4,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 13),
                                  TextFormField(
                                    controller: _destination,
                                    focusNode: _destinationFocus,
                                    textInputAction: TextInputAction.go,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: theme.textTheme.bodyMedium,
                                    onFieldSubmitted: (_) => _continue(),
                                    onChanged: (_) =>
                                        _companion.userInteracted(),
                                    decoration: InputDecoration(
                                      hintText: 'A place, landmark or address',
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        size: 19,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                      suffixIcon: IconButton(
                                        tooltip: 'Voice input',
                                        onPressed: _toggleHandsFree,
                                        icon: Icon(
                                          voice.enabled
                                              ? Icons.mic_rounded
                                              : Icons.mic_none_rounded,
                                          size: 19,
                                          color: scheme.secondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: _continue,
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            "Let's go together",
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 17,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (draft.checklist.isNotEmpty && !draft.isCasual) ...[
                              const SizedBox(height: 14),
                              _CompanionChecklistCard(
                                purposeSummary: draft.purposeSummary,
                                checklist: draft.checklist,
                                checkedItems: draft.checkedItems,
                                onToggleItem: (item) => ref
                                    .read(journeyDraftProvider.notifier)
                                    .toggleChecklistItem(item),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'A little inspiration',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _showPlaces,
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Explore'),
                                      SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_outward_rounded,
                                        size: 13,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final place in [
                                  'Lekki Phase 1',
                                  'Ikeja',
                                  'Ologolo',
                                ])
                                  ActionChip(
                                    avatar: Icon(
                                      Icons.north_east_rounded,
                                      size: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    label: Text(place),
                                    onPressed: () => _choosePlace(place),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 4,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    'MADE FOR THE WAY YOU MOVE',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 8,
                                      letterSpacing: 1.25,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.explore_outlined,
                                  size: 15,
                                  color: scheme.secondary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompanionChecklistCard extends StatelessWidget {
  const _CompanionChecklistCard({
    required this.purposeSummary,
    required this.checklist,
    required this.checkedItems,
    required this.onToggleItem,
  });

  final String purposeSummary;
  final List<String> checklist;
  final Set<String> checkedItems;
  final ValueChanged<String> onToggleItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checkedCount = checklist.where(checkedItems.contains).length;

    return Container(
      key: const ValueKey('companion-checklist-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 15,
                color: scheme.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  purposeSummary.isEmpty
                      ? 'BEFORE YOU STEP OUT'
                      : 'BEFORE YOU STEP OUT • ${purposeSummary.toUpperCase()}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.secondary,
                    letterSpacing: 1.1,
                    fontSize: 8.5,
                  ),
                ),
              ),
              Text(
                '$checkedCount/${checklist.length} ready',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in checklist)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onToggleItem(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      checkedItems.contains(item)
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 17,
                      color: checkedItems.contains(item)
                          ? scheme.secondary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          decoration: checkedItems.contains(item)
                              ? TextDecoration.lineThrough
                              : null,
                          color: checkedItems.contains(item)
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
