import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/navi_page.dart';
import '../../navigation/presentation/journey_map_preview.dart';
import 'journey_controller.dart';

class RoutePreviewScreen extends ConsumerWidget {
  const RoutePreviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(journeyDraftProvider);
    if (draft.destination.isEmpty) {
      return NaviPage(
        title: 'Your map',
        child: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Choose a destination first'),
          ),
        ),
      );
    }
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: JourneyMapPreview(
        destination: draft.destination,
        travelMode: draft.travelMode,
        onTravelModeChanged: ref
            .read(journeyDraftProvider.notifier)
            .setTravelMode,
        onBack: () => context.go('/'),
      ),
    );
  }
}
