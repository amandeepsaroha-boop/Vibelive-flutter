import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'vibe_colors.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(VibeColors.light, Brightness.light);

  static ThemeData dark() => _build(VibeColors.dark, Brightness.dark);

  static ThemeData _build(VibeColors c, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.accent,
          brightness: brightness,
        ).copyWith(
          primary: c.accent,
          onPrimary: c.onAccent,
          surface: c.bg,
          onSurface: c.text,
          error: TextColors.error,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppColors.transparent,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.accent,
        selectionColor: c.accentA(0.3),
        selectionHandleColor: c.accent,
      ),
      extensions: [c],
    );
  }
}
