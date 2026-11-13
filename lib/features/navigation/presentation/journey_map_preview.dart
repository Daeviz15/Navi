import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/interactive_navi_companion.dart';
import '../../journey/domain/journey_draft.dart';
import '../../journey/domain/journey_identity.dart';
import '../../journey/presentation/journey_companion_panel.dart';
import '../../journey/presentation/journey_controller.dart';
import '../../location/application/location_controller.dart';
import '../../location/domain/location_gateway.dart';
import '../../voice/application/voice_session_controller.dart';
import '../../voice/domain/voice_types.dart';
import '../application/navigation_controller.dart';
import '../data/maps_configuration.dart';
import '../data/reverse_geocoder.dart';
import '../domain/route_geometry.dart';
import '../domain/destination_selection.dart';
import 'journey_map_canvas.dart';

class JourneyMapPreview extends ConsumerStatefulWidget {
  const JourneyMapPreview({
    super.key,
    required this.destination,
    required this.travelMode,
    required this.onTravelModeChanged,
    required this.onBack,
    this.onEndTrip,
  });
  final String destination;
  final TravelMode travelMode;
  final ValueChanged<TravelMode> onTravelModeChanged;
  final VoidCallback onBack;
  final VoidCallback? onEndTrip;

  @override
  ConsumerState<JourneyMapPreview> createState() => _JourneyMapPreviewState();
}

class _JourneyMapPreviewState extends ConsumerState<JourneyMapPreview> {
  final _scroll = ScrollController();
  final _choices = GlobalKey();
  final _mapSection = GlobalKey();
  JourneyIdentity? _guidedIntent;
  DestinationSearchToken? _announcedToken;
  ConfirmedDestination? _shownConfirmation;
  int _scrollRevision = 0;
  bool _userScrolling = false;
  bool _userExplored = false;
  JourneyIdentity? _observedIntent;

  @override
  void dispose() {
    _scrollRevision++;
    _scroll.dispose();
    super.dispose();
  }

  void _focus(GlobalKey target, int revision) {
    if (!mounted || revision != _scrollRevision || _userScrolling) return;
    final targetContext = target.currentContext;
    if (targetContext == null || !_scroll.hasClients) return;
    unawaited(
      Scrollable.ensureVisible(
        targetContext,
        alignment: .08,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  void _guide(NavigationState navigation, VoiceSessionState voice) {
    if (_observedIntent != navigation.identity) {
      _observedIntent = navigation.identity;
      _userExplored = false;
    }
    final token = navigation.suggestions?.token;
    if (navigation.phase == NavigationPhase.choosePlace &&
        navigation.places.isNotEmpty &&
        token != null) {
      if (_guidedIntent != navigation.identity) {
        _guidedIntent = navigation.identity;
        final revision = ++_scrollRevision;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              ref.read(navigationControllerProvider).suggestions?.token !=
                  token ||
              ref.read(navigationControllerProvider).selected != null ||
              ModalRoute.of(context)?.isCurrent != true) {
            return;
          }
          if (!_userExplored) _focus(_choices, revision);
        });
      }
      if (_announcedToken != token) {
        _announcedToken = token;
        if (!voice.enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // The companion registers surface visibility in its own post-frame
            // callback. Run after all those callbacks, still outside widget build.
            Future.microtask(() {
              if (!mounted ||
                  ModalRoute.of(context)?.isCurrent != true ||
                  ref.read(navigationControllerProvider).suggestions?.token !=
                      token ||
                  ref.read(navigationControllerProvider).selected != null) {
                return;
              }
              unawaited(
                ref
                    .read(voiceSessionProvider.notifier)
                    .announceDestinationChoices(token),
              );
            });
          });
        }
      }
    }
    final confirmation = navigation.confirmation;
    if (confirmation != null && _shownConfirmation != confirmation) {
      _shownConfirmation = confirmation;
      final revision = ++_scrollRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            ref.read(navigationControllerProvider).confirmation !=
                confirmation ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        _focus(_mapSection, revision);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final configuration = ref.watch(mapsConfigurationProvider);
    final location = ref.watch(locationControllerProvider);
    final navigation = ref.watch(navigationControllerProvider);
    final currentArea = ref.watch(currentAreaProvider);
    final draft = ref.watch(journeyDraftProvider);
    final voice = ref.watch(voiceSessionProvider);
    _guide(navigation, voice);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _userScrolling = true;
            _userExplored = true;
            _scrollRevision++;
          } else if (notification is ScrollEndNotification) {
            _userScrolling = false;
          }
          return false;
        },
        child: SingleChildScrollView(
          controller: _scroll,
          key: const ValueKey('journey-map-preview'),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back to Navi',
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 21),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'navi.',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        'LAGOS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontSize: 8,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Map options',
                        icon: const Icon(Icons.more_horiz_rounded),
                        onSelected: (option) =>
                            _openOption(context, ref, option),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'notices',
                            child: Text('Map notices'),
                          ),
                          if (draft.checklist.isNotEmpty)
                            const PopupMenuItem(
                              value: 'essentials',
                              child: Text('Your essentials'),
                            ),
                          if (kDebugMode)
                            const PopupMenuItem(
                              value: 'diagnostics',
                              child: Text('Location diagnostics'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const JourneyCompanionPanel(),
                  if (draft.checklist.isNotEmpty && !draft.isCasual)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('journey-checklist-summary'),
                        onPressed: () =>
                            _openOption(context, ref, 'essentials'),
                        icon: const Icon(Icons.checklist_rounded, size: 17),
                        label: Text(
                          'Checklist · ${draft.checkedItems.length}/${draft.checklist.length} checked',
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (navigation.selected == null &&
                      navigation.places.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        key: const ValueKey('show-destination-choices'),
                        onPressed: () => _focus(_choices, ++_scrollRevision),
                        icon: const Icon(Icons.south_rounded, size: 16),
                        label: const Text('Next · confirm your destination'),
                      ),
                    ),
                  if (navigation.selected != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          navigation.route != null
                              ? 'Route preview · ${navigation.selected!.name}'
                              : navigation.message ?? 'Finding your route…',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  LayoutBuilder(
                    key: _mapSection,
                    builder: (context, constraints) => Container(
                      key: const ValueKey('boxed-journey-map'),
                      height: (constraints.maxWidth * .78).clamp(240.0, 340.0),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: configuration.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, _) => const Center(
                          child: Text('The map is unavailable right now.'),
                        ),
                        data: (value) => value == MapsConfiguration.ready
                            ? JourneyMapCanvas(
                                location: location,
                                navigation: navigation,
                              )
                            : const Center(
                                child: Text(
                                  'The map is unavailable right now.',
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud_rounded,
                        size: 15,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text('You', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 16),
                      if (navigation.selected != null)
                        const Icon(
                          Icons.cloud_rounded,
                          size: 15,
                          color: Color(0xFF4B9FFF),
                        ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          navigation.selected != null
                              ? 'Confirmed destination'
                              : 'Choose your destination below',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AnimatedContainer(
                    key: const ValueKey('destination-confirmation-card'),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 350),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: navigation.phase == NavigationPhase.choosePlace
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          navigation.selected == null
                              ? 'DESTINATION TO CONFIRM'
                              : 'DESTINATION',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontSize: 8,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          navigation.selected?.name ?? widget.destination,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (navigation.selected != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            navigation.selected!.address,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        if (navigation.selected == null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const ValueKey('refine-map-destination'),
                              onPressed: () => _refineDestination(context, ref),
                              icon: const Icon(
                                Icons.edit_location_alt_outlined,
                                size: 16,
                              ),
                              label: const Text('Refine destination'),
                            ),
                          ),
                        if (navigation.selected != null &&
                            navigation.places.length > 1)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () =>
                                  _openPlacePicker(context, ref, navigation),
                              icon: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 16,
                              ),
                              label: Text(
                                'Change spot (${navigation.places.length})',
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final mode in TravelMode.values)
                              ChoiceChip(
                                showCheckmark: false,
                                selected: widget.travelMode == mode,
                                avatar: Icon(
                                  mode == TravelMode.bus
                                      ? Icons.directions_bus_outlined
                                      : Icons.directions_walk_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  mode == TravelMode.bus ? 'By bus' : 'On foot',
                                ),
                                onSelected: (_) =>
                                    widget.onTravelModeChanged(mode),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          currentArea != null
                              ? '${location.caption} · Around $currentArea'
                              : location.caption,
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (!location.hasCurrentFix ||
                            location.quality != FixQuality.usable) ...[
                          const SizedBox(height: 5),
                          Text(
                            _locationExplanation(location),
                            style: theme.textTheme.bodySmall,
                          ),
                          if (location.phase == LocationPhase.servicesOff ||
                              location.phase == LocationPhase.deniedForever ||
                              location.approximate)
                            TextButton(
                              onPressed: ref
                                  .read(locationControllerProvider.notifier)
                                  .openSettings,
                              child: const Text('Location settings'),
                            )
                          else if (location.phase != LocationPhase.acquiring &&
                              location.phase != LocationPhase.requesting &&
                              location.phase != LocationPhase.suspended)
                            TextButton(
                              onPressed: ref
                                  .read(locationControllerProvider.notifier)
                                  .enable,
                              child: const Text('Enable location'),
                            ),
                        ],
                        const SizedBox(height: 10),
                        _routeDetails(context, ref, navigation),
                        if (widget.onEndTrip != null) ...[
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const ValueKey('end-trip-button'),
                            onPressed: widget.onEndTrip,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(
                                color: scheme.error.withValues(alpha: .45),
                              ),
                            ),
                            icon: const Icon(Icons.flag_outlined, size: 17),
                            label: const Text('End trip'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _locationExplanation(LocationState state) {
    if (state.quality == FixQuality.stale) {
      return 'The last estimate is out of date. Waiting for a fresh reading.';
    }
    if (state.quality == FixQuality.uncertain) {
      return 'The shaded area shows uncertainty. Your exact position is not confirmed.';
    }
    return 'Allow location to see where you are. You can still explore the map.';
  }

  Widget _routeDetails(
    BuildContext context,
    WidgetRef ref,
    NavigationState state,
  ) {
    final theme = Theme.of(context);
    final controller = ref.read(navigationControllerProvider.notifier);
    if (state.phase == NavigationPhase.searching ||
        state.phase == NavigationPhase.planning) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.phase == NavigationPhase.searching
                ? 'Finding matching places…'
                : 'Finding a real route…',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(minHeight: 2),
        ],
      );
    }
    if (state.phase == NavigationPhase.choosePlace && state.places.isNotEmpty) {
      return Column(
        key: _choices,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Confirm the exact place',
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check the address, then tap to confirm. Or tap Navi and say an option number.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const InteractiveNaviCompanion(
                size: 64,
                controlKey: ValueKey('destination-navi-control'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ref.watch(voiceSessionProvider).enabled
                      ? ref.watch(voiceSessionProvider).caption
                      : 'Tap Navi here to choose by voice. Try “option two”.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          for (final (index, place) in state.places.indexed)
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                key: ValueKey('confirm-destination-${place.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.place_outlined, size: 18),
                title: Text('${index + 1}. ${place.name}'),
                subtitle: Text(place.address),
                trailing: const Icon(Icons.check_rounded, size: 16),
                onTap: () => controller.confirm(
                  DestinationSelectionRequest(
                    token: state.suggestions!.token,
                    placeId: place.id,
                    source: DestinationConfirmationSource.tap,
                  ),
                ),
              ),
            ),
        ],
      );
    }
    if (state.route != null) {
      final route = state.route!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.progress.caption,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: state.refreshing || !state.refreshAllowed
                    ? null
                    : controller.plan,
                child: Text(state.refreshing ? 'Refreshing…' : 'Refresh'),
              ),
            ],
          ),
          Text(
            'Route length · ${formatRouteDistance(route.distanceMeters)}',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            'The flowing line previews the route direction, not your movement.',
            style: theme.textTheme.bodySmall,
          ),
          if (state.estimatesStale)
            Text(
              'Previous route shown. Its planning estimates need refreshing.',
              style: theme.textTheme.bodySmall,
            )
          else if (!route.isRoadFallback)
            Text(
              'Planning time from last refresh · ${(route.durationSeconds / 60).ceil()} min',
              style: theme.textTheme.bodySmall,
            ),
          if (state.refreshing) const LinearProgressIndicator(minHeight: 2),
          if (state.message != null)
            Text(state.message!, style: theme.textTheme.bodySmall),
          if (route.isRoadFallback)
            Text(
              'Showing Lagos road corridor (live bus schedule unavailable).',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          state.message ?? 'Confirm your destination to see a route.',
          style: theme.textTheme.bodySmall,
        ),
        if (state.needsSetup)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Icon(Icons.link_off_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Map connection required')),
              ],
            ),
          )
        else if (state.phase != NavigationPhase.waitingForLocation)
          TextButton(
            onPressed: state.selected != null && !state.refreshAllowed
                ? null
                : state.selected == null
                ? controller.search
                : controller.plan,
            child: Text(
              state.selected == null
                  ? 'Retry destination lookup'
                  : 'Refresh route',
            ),
          ),
      ],
    );
  }

  void _openPlacePicker(
    BuildContext context,
    WidgetRef ref,
    NavigationState state,
  ) {
    final controller = ref.read(navigationControllerProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Confirm exact destination',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final place in state.places)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        state.selected?.id == place.id
                            ? Icons.radio_button_checked_rounded
                            : Icons.place_outlined,
                        size: 18,
                      ),
                      title: Text(place.name),
                      subtitle: Text(place.address),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        controller.confirm(
                          DestinationSelectionRequest(
                            token: state.suggestions!.token,
                            placeId: place.id,
                            source: DestinationConfirmationSource.tap,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refineDestination(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(journeyDraftProvider);
    var query = draft.destination;
    final form = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void submit() {
          if (form.currentState!.validate()) {
            Navigator.pop(dialogContext, query.trim());
          }
        }

        return AlertDialog(
          title: const Text('Find the exact place'),
          content: Form(
            key: form,
            child: TextFormField(
              initialValue: query,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Place or address',
                helperText: draft.checklist.isEmpty
                    ? null
                    : 'A new destination clears this checklist.',
                helperMaxLines: 2,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a place or address.'
                  : null,
              onChanged: (value) => query = value,
              onFieldSubmitted: (_) => submit(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(onPressed: submit, child: const Text('Find places')),
          ],
        );
      },
    );
    if (!context.mounted ||
        value == null ||
        value.toLowerCase() == draft.destination.toLowerCase() ||
        ref.read(journeyDraftProvider).identity != draft.identity) {
      return;
    }
    // An explicit new query has no confirmed geographic relationship to the
    // old one. Reset preparation instead of attaching it to a different place.
    ref.read(journeyDraftProvider.notifier).switchTripDestination(value);
  }

  void _openOption(BuildContext context, WidgetRef ref, String option) {
    if (option == 'notices') {
      showLicensePage(context: context, applicationName: 'Navi');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: option == 'essentials'
              ? Consumer(
                  builder: (context, ref, _) {
                    final draft = ref.watch(journeyDraftProvider);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Your essentials',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (final item in draft.checklist)
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(item),
                                    value: draft.checkedItems.contains(item),
                                    onChanged: (_) => ref
                                        .read(journeyDraftProvider.notifier)
                                        .toggleChecklistItem(item),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                )
              : Consumer(
                  builder: (context, ref, _) {
                    final location = ref.watch(locationControllerProvider);
                    return Text(
                      'Location: ${location.phase.name} · ${location.quality.name}\n'
                      'Reported uncertainty: ${location.fix?.accuracyMeters.toStringAsFixed(0) ?? "—"} m',
                      style: Theme.of(context).textTheme.bodySmall,
                    );
                  },
                ),
        ),
      ),
    );
  }
}
