import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Session-only for MVP foundation. Persist preference in a repository later.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void setLightMode(bool enabled) {
    state = enabled ? ThemeMode.light : ThemeMode.dark;
  }
}
