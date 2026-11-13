import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/journey/application/voice_journey_bridge.dart';

import '../core/theme/navi_theme.dart';
import 'router.dart';

class NaviApp extends ConsumerWidget {
  const NaviApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(voiceJourneyBridgeProvider);

    // Makes the Android bottom navigation area match Navi's dark surface.
    // The OS may override navigation-bar colouring on edge-to-edge devices.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: NaviColors.midnight,
        systemNavigationBarDividerColor: NaviColors.midnight,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Navi',
        theme: NaviTheme.dark,
        darkTheme: NaviTheme.dark,
        themeMode: ThemeMode.dark,
        routerConfig: naviRouter,
      ),
    );
  }
}
