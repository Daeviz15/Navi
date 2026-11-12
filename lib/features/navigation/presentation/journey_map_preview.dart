import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../journey/domain/journey_draft.dart';
import '../../journey/presentation/journey_companion_panel.dart';
import '../../journey/presentation/journey_controller.dart';
import '../../location/application/location_controller.dart';
import '../../location/domain/location_gateway.dart';
import '../application/navigation_controller.dart';
import '../data/maps_configuration.dart';
import 'journey_map_canvas.dart';

class JourneyMapPreview extends ConsumerWidget {
  const JourneyMapPreview({
    super.key,
    required this.destination,
    required this.travelMode,
    required this.onTravelModeChanged,
    required this.onBack,
  });
  final String destination;
  final TravelMode travelMode;
  final ValueChanged<TravelMode> onTravelModeChanged;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuration = ref.watch(mapsConfigurationProvider);
    final location = ref.watch(locationControllerProvider);
    final navigation = ref.watch(navigationControllerProvider);
    final draft = ref.watch(journeyDraftProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
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
                      onPressed: onBack,
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
                      onSelected: (option) => _openOption(context, ref, option),
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
                      onPressed: () => _openOption(context, ref, 'essentials'),
                      icon: const Icon(Icons.checklist_rounded, size: 17),
                      label: Text(
                        'Checklist · ${draft.checkedItems.length}/${draft.checklist.length} checked',
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                LayoutBuilder(
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
                              child: Text('The map is unavailable right now.'),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.cloud_rounded, size: 15, color: scheme.primary),
                    const SizedBox(width: 5),
                    Text('You', style: theme.textTheme.bodySmall),
                    const SizedBox(width: 16),
                    const Icon(
                      Icons.cloud_rounded,
                      size: 15,
                      color: Color(0xFF4B9FFF),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Confirmed destination',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'DESTINATION',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontSize: 8,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        navigation.selected?.name ?? destination,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (navigation.selected != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          navigation.selected!.address,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final mode in TravelMode.values)
                            ChoiceChip(
                              showCheckmark: false,
                              selected: travelMode == mode,
                              avatar: Icon(
                                mode == TravelMode.bus
                                    ? Icons.directions_bus_outlined
                                    : Icons.directions_walk_rounded,
                                size: 16,
                              ),
                              label: Text(
                                mode == TravelMode.bus ? 'By bus' : 'On foot',
                              ),
                              onSelected: (_) => onTravelModeChanged(mode),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(location.caption, style: theme.textTheme.bodyMedium),
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
                    ],
                  ),
                ),
              ],
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
      return Text(
        state.phase == NavigationPhase.searching
            ? 'Finding matching places…'
            : 'Finding a real route…',
        style: theme.textTheme.bodySmall,
      );
    }
    if (state.phase == NavigationPhase.choosePlace && state.places.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirm the exact place', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final place in state.places)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.place_outlined, size: 18),
              title: Text(place.name),
              subtitle: Text(place.address),
              trailing: const Icon(Icons.arrow_forward_rounded, size: 16),
              onTap: () => controller.select(place),
            ),
        ],
      );
    }
    if (state.route != null) {
      final route = state.route!;
      return Row(
        children: [
          Expanded(
            child: Text(
              'Estimate · ${(route.durationSeconds / 60).ceil()} min · '
              '${(route.distanceMeters / 1000).toStringAsFixed(1)} km',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: controller.plan, child: const Text('Refresh')),
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
        if (state.phase != NavigationPhase.waitingForLocation)
          TextButton(
            onPressed: state.selected == null
                ? controller.search
                : controller.plan,
            child: Text(
              state.selected == null ? 'Find destination' : 'Refresh route',
            ),
          ),
      ],
    );
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
