import 'package:flutter/material.dart';

abstract final class NaviColors {
  static const midnight = Color(0xFF000000);
  static const surface = Color(0xFF111110);
  static const surfaceRaised = Color(0xFF1B1B18);
  static const gold = Color(0xFFCCA632);
  static const goldInk = Color(0xFF785C0C);
  static const cloud = Color(0xFFF0EFE9);
  static const mist = Color(0xFF999990);
  static const pearl = Color(0xFFF6F4ED);
  static const pearlSurface = Color(0xFFFFFEFA);
  static const pearlRaised = Color(0xFFECE9DF);
  static const ink = Color(0xFF23241E);
  static const inkMuted = Color(0xFF6D6D61);
}

abstract final class NaviTheme {
  static final dark = _build(Brightness.dark);
  static final light = _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final foreground = dark ? NaviColors.cloud : NaviColors.ink;
    final muted = dark ? NaviColors.mist : NaviColors.inkMuted;
    final background = dark ? NaviColors.midnight : NaviColors.pearl;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: NaviColors.gold,
          brightness: brightness,
        ).copyWith(
          primary: NaviColors.gold,
          onPrimary: const Color(0xFF19170C),
          primaryContainer: dark
              ? const Color(0xFF272313)
              : const Color(0xFFF0E5BC),
          onPrimaryContainer: dark ? NaviColors.gold : NaviColors.goldInk,
          secondary: dark ? NaviColors.gold : NaviColors.goldInk,
          surface: dark ? NaviColors.surface : NaviColors.pearlSurface,
          surfaceContainerHighest: dark
              ? NaviColors.surfaceRaised
              : NaviColors.pearlRaised,
          onSurface: foreground,
          onSurfaceVariant: muted,
          outline: dark ? const Color(0xFF45453C) : const Color(0xFFBDBAAD),
          outlineVariant: dark
              ? const Color(0xFF272722)
              : const Color(0xFFDDDACE),
          surfaceTint: Colors.transparent,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Syne',
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );
    final text = base.textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );
    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontSize: 28,
          height: 1.18,
          fontWeight: FontWeight.w600,
          letterSpacing: -1.1,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontSize: 25,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -.6,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: text.titleSmall?.copyWith(fontSize: 12),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 14, height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 12, height: 1.55),
        bodySmall: text.bodySmall?.copyWith(
          fontSize: 11,
          height: 1.5,
          color: muted,
        ),
        labelLarge: text.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: text.labelMedium?.copyWith(fontSize: 11),
        labelSmall: text.labelSmall?.copyWith(
          fontSize: 9,
          letterSpacing: 1.8,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Syne',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      iconTheme: IconThemeData(size: 20, color: foreground),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        hintStyle: TextStyle(color: muted, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NaviColors.gold),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          elevation: 0,
          shape: shape,
          textStyle: const TextStyle(
            fontFamily: 'Syne',
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: foreground,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: shape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.secondary,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontFamily: 'Syne', fontSize: 12),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          fontFamily: 'Syne',
          fontSize: 11,
          color: foreground,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(
          fontFamily: 'Syne',
          color: foreground,
          fontSize: 12,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: shape,
      ),
    );
  }
}
