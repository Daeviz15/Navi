import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/navi_page.dart';
import '../domain/journey_draft.dart';
import 'journey_controller.dart';

class RoutePreviewScreen extends ConsumerWidget {
  const RoutePreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(journeyDraftProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (draft.destination.isEmpty) {
      return NaviPage(
        title: 'Journey overview',
        child: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Choose a destination first'),
          ),
        ),
      );
    }

    final purposeText = switch (draft.purpose) {
      JourneyPurpose.errand => 'An errand to run',
      JourneyPurpose.visit => 'Someone to see',
      JourneyPurpose.directionsOnly => 'Somewhere to be',
      JourneyPurpose.unspecified => 'A fresh adventure',
    };

    return NaviPage(
      title: 'Journey overview',
      step: '02 / 02',
      onBack: () => context.go('/prepare'),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'THE PLAN, AT A GLANCE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.secondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'A good day\nstarts somewhere.',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              purposeText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.trip_origin_rounded,
                        size: 17,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'STARTING POINT',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 8,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Not selected yet',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 1,
                        height: 22,
                        color: scheme.outline,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 19,
                        color: scheme.secondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'YOUR DESTINATION',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 8,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              draft.destination,
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(
              'How are you getting there?',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final mode in TravelMode.values)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: Icon(
                      mode == TravelMode.bus
                          ? Icons.directions_bus_outlined
                          : Icons.directions_walk_rounded,
                      size: 17,
                      color: draft.travelMode == mode
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                    label: Text(mode == TravelMode.bus ? 'By bus' : 'On foot'),
                    selected: draft.travelMode == mode,
                    selectedColor: scheme.primaryContainer,
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: draft.travelMode == mode
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
                    onSelected: (_) => ref
                        .read(journeyDraftProvider.notifier)
                        .setTravelMode(mode),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(Icons.map_outlined, size: 30, color: scheme.secondary),
                  const SizedBox(height: 14),
                  Text(
                    'Your route will appear here',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Live routes and arrival estimates aren't available yet.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.near_me_outlined, size: 16),
              label: const Text('Navigation coming soon'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                ref.read(journeyDraftProvider.notifier).reset();
                context.go('/');
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Start a new journey'),
            ),
          ],
        ),
      ),
    );
  }
}
