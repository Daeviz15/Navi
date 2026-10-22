import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/navi_page.dart';
import '../../journey/domain/journey_draft.dart';
import '../../journey/presentation/journey_controller.dart';

class PreparationScreen extends ConsumerWidget {
  const PreparationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(journeyDraftProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (draft.destination.isEmpty) {
      return NaviPage(
        title: 'Plan your journey',
        child: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Choose a destination first'),
          ),
        ),
      );
    }

    void selectPurpose(JourneyPurpose purpose) {
      ref.read(journeyDraftProvider.notifier).setPurpose(purpose);
      context.go('/preview');
    }

    return NaviPage(
      title: 'Plan your journey',
      step: '01 / 02',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A JOURNEY THAT FITS YOU',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.secondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'What brings you there?',
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'A little context goes a long way.\nPick what feels right, or keep it simple.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.place_outlined, color: scheme.secondary, size: 21),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HEADING TO',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontSize: 8,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          draft.destination,
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            _PurposeCard(
              title: "I'm running an errand",
              subtitle: 'Make this stop part of the plan.',
              icon: Icons.checklist_rounded,
              onTap: () => selectPurpose(JourneyPurpose.errand),
            ),
            const SizedBox(height: 10),
            _PurposeCard(
              title: "I'm visiting someone",
              subtitle: 'Good company is worth the trip.',
              icon: Icons.people_alt_outlined,
              onTap: () => selectPurpose(JourneyPurpose.visit),
            ),
            const SizedBox(height: 10),
            _PurposeCard(
              title: 'Just show me the way',
              subtitle: 'Keep it simple. Destination first.',
              icon: Icons.turn_right_rounded,
              onTap: () => selectPurpose(JourneyPurpose.directionsOnly),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Your journey, your pace.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.arrow_back_rounded, size: 15),
              label: const Text('Change destination'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurposeCard extends StatelessWidget {
  const _PurposeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
