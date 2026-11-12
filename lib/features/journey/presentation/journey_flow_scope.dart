import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../location/application/location_controller.dart';

/// Owns foreground location across initialization -> map, not just one page.
class JourneyFlowScope extends ConsumerStatefulWidget {
  const JourneyFlowScope({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<JourneyFlowScope> createState() => _JourneyFlowScopeState();
}

class _JourneyFlowScopeState extends ConsumerState<JourneyFlowScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A permission dialog makes Android inactive; only actual backgrounding
    // should cancel acquisition. Resume never prompts permission again.
    if (state == AppLifecycleState.inactive) return;
    unawaited(
      ref.read(locationControllerProvider.notifier).setVisible(
        state == AppLifecycleState.resumed,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(locationControllerProvider);
    return widget.child;
  }
}
