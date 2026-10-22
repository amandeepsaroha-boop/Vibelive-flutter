import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// Colors of the Personal Info screen (RN `PersonalInfoScreen` `theme`).
@immutable
class PersonalInfoPalette {
  const PersonalInfoPalette._({
    required this.isDark,
    required this.bg,
    required this.text,
    required this.muted,
    required this.border,
    required this.card,
    required this.soft,
    required this.sheet,
    required this.accent,
  });

  factory PersonalInfoPalette.of(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    return PersonalInfoPalette._(
      isDark: dark,
      bg: dark ? DarkColors.bg : LightColors.bg,
      text: dark ? AppColors.white : LightColors.text,
      muted: dark ? AppColors.whiteA(0.48) : AppColors.blackA(0.42),
      border: dark ? AppColors.whiteA(0.09) : LightColors.border,
      card: dark ? DarkColors.surface : AppColors.whiteA(0.92),
      soft: dark ? DarkColors.borderSubtle : AppColors.blackA(0.04),
      sheet: dark ? AppColors.darkSurface : AppColors.white,
      accent: c.accent,
    );
  }

  final bool isDark;
  final Color bg;
  final Color text;
  final Color muted;
  final Color border;

  /// Field and section fill.
  final Color card;

  /// Disabled field / icon-button fill.
  final Color soft;

  /// Picker sheet fill.
  final Color sheet;

  /// RN `COLORS.brand.rose`.
  final Color accent;

  Color accentA(double opacity) => accent.withValues(alpha: opacity);
}
