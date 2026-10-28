import 'dart:async';

import 'package:flutter/material.dart';

import '../storage/app_prefs.dart';

/// System / dark / light, persisted (same key as the RN theme store).
/// Default follows the system, like RN.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(super.value);

  static const _prefsKey = 'vibe_theme_preference';

  /// Set once the old choice has been cleared (see [load]).
  static const _deviceDefaultKey = 'vibe_theme_device_default_v1';

  /// Synchronous: [AppPrefs] is already loaded.
  ///
  /// Once per install: a light / dark saved by the old on/off switch (or
  /// kept from RN) is dropped, so the app starts on Device, the default.
  /// That switch had no way back to it; choices made in the new
  /// Device / Light / Dark control are kept as usual.
  factory ThemeController.load() {
    if (AppPrefs.getString(_deviceDefaultKey) == null) {
      unawaited(AppPrefs.remove(_prefsKey));
      unawaited(AppPrefs.setString(_deviceDefaultKey, '1'));
      return ThemeController(ThemeMode.system);
    }
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
}
