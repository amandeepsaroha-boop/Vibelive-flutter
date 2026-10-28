import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';

void main() {
  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPrefs.init();
  });

  test(
    'a light / dark from the old switch gives way to Device, once',
    () async {
      await AppPrefs.setString('vibe_theme_preference', 'dark'); // old switch
      expect(ThemeController.load().value, ThemeMode.system);
      await Future<void>.delayed(Duration.zero);
      expect(AppPrefs.getString('vibe_theme_preference'), isNull);

      // From then on, a choice in the new control sticks.
      await ThemeController.load().setMode(ThemeMode.dark);
      expect(ThemeController.load().value, ThemeMode.dark);
      await ThemeController.load().setMode(ThemeMode.system);
      expect(ThemeController.load().value, ThemeMode.system);
    },
  );
}
