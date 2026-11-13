import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/interactive_navi_companion.dart';
import '../../character/presentation/companion_controller.dart';
import '../../journey/application/active_trip_coordinator.dart';
import '../../journey/domain/journey_draft.dart';
import '../../journey/presentation/journey_controller.dart';
import '../../location/application/location_controller.dart';
import '../../navigation/application/navigation_controller.dart';
import '../../navigation/data/reverse_geocoder.dart';
import '../../voice/application/voice_session_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final _destination = TextEditingController();
  final _destinationFocus = FocusNode();
  final _checklistKey = GlobalKey();
  late VoiceSessionController _voice;
  late CompanionController _companion;

  @override
  void initState() {
    super.initState();
    _destination.text = ref.read(journeyDraftProvider).destination;
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
      transient: state == AppLifecycleState.inactive,
    );
    _companion.setVisible(state == AppLifecycleState.resumed);
    if (state != AppLifecycleState.inactive &&
        ref.read(journeyDraftProvider).isActive) {
      unawaited(
        ref
            .read(locationControllerProvider.notifier)
            .setVisible(state == AppLifecycleState.resumed),
      );
    }
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
    final voice = ref.watch(voiceSessionProvider);
    final draft = ref.watch(journeyDraftProvider);
    final isActiveTrip = draft.isActive;
    final navigation = isActiveTrip
        ? ref.watch(navigationControllerProvider)
        : const NavigationState();
    final currentArea = isActiveTrip ? ref.watch(currentAreaProvider) : null;
    final activeTitle = navigation.selected?.name ?? draft.destination;
    final routeSummary = navigation.routeSummary;
    ref.listen(journeyDraftProvider, (previous, next) {
      if (next.destination != previous?.destination &&
          _destination.text != next.destination) {
        _destination.text = next.destination;
      }
      if (next.checklist.isNotEmpty && (previous?.checklist.isEmpty ?? true)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _checklistKey.currentContext != null) {
            unawaited(
              Scrollable.ensureVisible(
                _checklistKey.currentContext!,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 380),
                alignment: 0.15,
              ),
            );
          }
        });
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
                                    isActiveTrip
                                        ? 'TRIP IN PROGRESS · ON THE WAY'
                                        : 'A LITTLE COMPANY. A BETTER JOURNEY.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: isActiveTrip
                                          ? scheme.secondary
                                          : scheme.onSurfaceVariant,
                                      fontSize: 8,
                                      letterSpacing: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 13),
                            if (isActiveTrip)
                              Text.rich(
                                TextSpan(
                                  text: 'In transit to\n',
                                  children: [
                                    TextSpan(
                                      text: activeTitle,
                                      style: TextStyle(color: scheme.secondary),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.displaySmall,
                              )
                            else
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
                              isActiveTrip
                                  ? [
                                      if (currentArea != null)
                                        'Around $currentArea',
                                      ?routeSummary,
                                      if (currentArea == null &&
                                          routeSummary == null)
                                        'Your route stays active until you end your trip.',
                                    ].join(' · ')
                                  : "Your plans. My company. Let's find a way.",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                            SizedBox(height: compact ? 14 : 22),
                            Center(
                              child: InteractiveNaviCompanion(size: stageSize),
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
                            if (isActiveTrip)
                              _ActiveTripCard(
                                destination: activeTitle,
                                address: navigation.selected?.address,
                                travelMode: draft.travelMode,
                                currentArea: currentArea,
                                routeSummary: routeSummary,
                                destinationConfirmed:
                                    navigation.selected != null,
                                onResumeMap: () {
                                  _destinationFocus.unfocus();
                                  _voice.suspendForNavigation();
                                  context.go('/preview');
                                },
                                onEndTrip: () => unawaited(
                                  ref
                                      .read(activeTripCoordinatorProvider)
                                      .endTrip(
                                        expectedIdentity: draft.identity,
                                      ),
                                ),
                              )
                            else
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                        hintText:
                                            'A place, landmark or address',
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          size: 19,
                                          color: scheme.onSurfaceVariant,
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
                            if (draft.checklist.isNotEmpty &&
                                !draft.isCasual) ...[
                              const SizedBox(height: 14),
                              _CompanionChecklistCard(
                                key: _checklistKey,
                                purposeSummary: draft.purposeSummary,
                                checklist: draft.checklist,
                                checkedItems: draft.checkedItems,
                                onToggleItem: (item) => ref
                                    .read(journeyDraftProvider.notifier)
                                    .toggleChecklistItem(item),
                              ),
                            ],
                            if (!isActiveTrip) ...[
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
                            ],
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

class _ActiveTripCard extends StatelessWidget {
  const _ActiveTripCard({
    required this.destination,
    required this.address,
    required this.travelMode,
    required this.currentArea,
    required this.routeSummary,
    required this.destinationConfirmed,
    required this.onResumeMap,
    required this.onEndTrip,
  });

  final String destination;
  final String? address;
  final TravelMode travelMode;
  final String? currentArea;
  final String? routeSummary;
  final bool destinationConfirmed;
  final VoidCallback onResumeMap;
  final VoidCallback onEndTrip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final modeLabel = travelMode == TravelMode.bus ? 'By bus' : 'On foot';

    return Container(
      key: const ValueKey('active-trip-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.secondary.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.navigation_rounded, size: 14, color: scheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'YOUR JOURNEY · ${modeLabel.toUpperCase()}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.secondary,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(destination, style: theme.textTheme.titleMedium),
          if (!destinationConfirmed) ...[
            const SizedBox(height: 5),
            Text(
              'Confirm the exact address on the map or with Navi.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (address != null && address!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(address!, style: theme.textTheme.bodySmall),
          ],
          if (currentArea != null || routeSummary != null) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (currentArea != null) 'Now near $currentArea',
                if (routeSummary != null) routeSummary,
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('resume-map-button'),
            onPressed: onResumeMap,
            icon: const Icon(Icons.map_outlined, size: 17),
            label: const Text('Resume map'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('home-end-trip-button'),
            onPressed: onEndTrip,
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: .45)),
            ),
            icon: const Icon(Icons.flag_outlined, size: 17),
            label: const Text('End trip'),
          ),
        ],
      ),
    );
  }
}

class _CompanionChecklistCard extends StatelessWidget {
  const _CompanionChecklistCard({
    super.key,
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
