import 'package:flutter/material.dart';

import '../storage/app_prefs.dart';

/// System / dark / light, persisted (same key as the RN theme store).
/// Default follows the system, like RN.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(super.value);

  static const _prefsKey = 'vibe_theme_preference';

  /// Synchronous: [AppPrefs] is already loaded.
  factory ThemeController.load() {
    return ThemeController(switch (AppPrefs.getString(_prefsKey)) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    });
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == value) return;
    value = mode;
    await AppPrefs.setString(_prefsKey, switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    });
  }

  /// RN `toggleDark`: flips relative to what is currently on screen.
  Future<void> toggle(BuildContext context) => setMode(
    Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark,
  );
}
