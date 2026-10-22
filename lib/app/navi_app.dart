import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/navi_theme.dart';
import '../core/theme/theme_mode_controller.dart';
import 'router.dart';

class NaviApp extends ConsumerWidget {
  const NaviApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isLight = themeMode == ThemeMode.light;
    final systemBackground = isLight ? NaviColors.pearl : NaviColors.midnight;

    // Makes the Android bottom navigation area match the chosen theme.
    // The OS may override navigation-bar colouring on edge-to-edge devices.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: systemBackground,
        systemNavigationBarDividerColor: systemBackground,
        systemNavigationBarIconBrightness: isLight
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Navi',
        theme: NaviTheme.light,
        darkTheme: NaviTheme.dark,
        themeMode: themeMode,
        routerConfig: naviRouter,
      ),
    );
  }
}
