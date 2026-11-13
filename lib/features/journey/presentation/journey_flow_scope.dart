import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../location/application/location_controller.dart';
import 'journey_controller.dart';

/// Owns foreground location across initialization -> map, and keeps GPS live
/// across Home <-> Map once a trip becomes active until the user ends it.
class JourneyFlowScope extends ConsumerStatefulWidget {
  const JourneyFlowScope({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<JourneyFlowScope> createState() => _JourneyFlowScopeState();
}

class _JourneyFlowScopeState extends ConsumerState<JourneyFlowScope>
    with WidgetsBindingObserver {
  late final LocationController _location;
  bool _tripActive = false;

  @override
  void initState() {
    super.initState();
    _location = ref.read(locationControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_location.setVisible(true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A permission dialog makes Android inactive; only actual backgrounding
    // should cancel acquisition. Resume never prompts permission again.
    if (state == AppLifecycleState.inactive) return;
    unawaited(_location.setVisible(state == AppLifecycleState.resumed));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_tripActive) {
      unawaited(_location.setVisible(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _tripActive = ref.watch(
      journeyDraftProvider.select((draft) => draft.isActive),
    );
    ref.watch(locationControllerProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) context.go('/');
      },
      child: widget.child,
    );
  }
}
