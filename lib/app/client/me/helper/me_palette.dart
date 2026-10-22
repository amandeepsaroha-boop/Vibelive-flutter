import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// The ME tab's card colors (RN MeCard `theme` memo). One const instance per
/// mode, so reading it costs nothing.
@immutable
class MePalette {
  const MePalette._({
    required this.isDark,
    required this.accent,
    required this.onAccent,
    required this.text,
    required this.muted,
    required this.cardBg,
    required this.cardBorder,
    required this.pillBg,
    required this.activeBg,
    required this.activeFg,
    required this.profileBg,
    required this.profileBorder,
    required this.avatarBg,
    required this.dotBorder,
    required this.offline,
    required this.pillText,
    required this.earningsBg,
  });

  static const dark = MePalette._(
    isDark: true,
    accent: BrandColors.lime,
    onAccent: AppColors.black,
    text: AppColors.white,
    muted: TextColors.dim,
    cardBg: DarkColors.surface,
    cardBorder: DarkColors.border,
    pillBg: Color(0x0DFFFFFF), // white 5%
    activeBg: AppColors.white,
    activeFg: AppColors.black,
    profileBg: Color(0x08FFFFFF), // white 3%
    profileBorder: Color(0x14FFFFFF), // white 8%
    avatarBg: DarkColors.surfaceVariant,
    dotBorder: DarkColors.borderDarkest,
    offline: Color(0x59FFFFFF), // white 35%
    pillText: AppColors.white,
    earningsBg: DarkColors.surface,
  );

  static const light = MePalette._(
    isDark: false,
    accent: BrandColors.purple,
    onAccent: AppColors.white,
    text: LightColors.text,
    muted: LightColors.muted,
    cardBg: LightColors.surface,
    cardBorder: Color(0x1A000000), // black 10%
    pillBg: Color(0xF2FFFFFF), // white 95%
    activeBg: AppColors.black,
    activeFg: AppColors.white,
    profileBg: AppColors.white,
    profileBorder: Color(0x14000000), // black 8%
    avatarBg: AppColors.bgGrayLight,
    dotBorder: AppColors.white,
    offline: Color(0x4D000000), // black 30%
    pillText: AppColors.slate900,
    earningsBg: AppColors.slate900,
  );

  static MePalette of(BuildContext context) =>
      context.colors.isDark ? dark : light;

  final bool isDark;

  /// RN `brand.rose`: lime in dark, purple in light.
  final Color accent;
  final Color onAccent;
  final Color text;
  final Color muted;
  final Color cardBg;
  final Color cardBorder;

  /// Segmented controls (availability, Dashboard | Settings).
  final Color pillBg;
  final Color activeBg;
  final Color activeFg;

  final Color profileBg;
  final Color profileBorder;
  final Color avatarBg;
  final Color dotBorder;

  /// Status dot of an offline / switched-off host.
  final Color offline;

  /// Availability pill label.
  final Color pillText;

  /// Lifetime earnings card (always reads as a dark card).
  final Color earningsBg;
}

/// Fixed colors of the ME tab that are not in the app palette (RN literals).
abstract final class MeColors {
  /// RESOURCES category (`menu-data.js`).
  static const resources = Color(0xFF4E63BF);

  /// "Company's Profile" chip.
  static const companyBg = Color(0xFFE3F2FD);
  static const companyBorder = Color(0xFF90CAF9);
  static const companyText = Color(0xFF1565C0);
}
