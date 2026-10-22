import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// RN ReferralScreen `theme` memo, one const instance per mode.
@immutable
class ReferralPalette {
  const ReferralPalette._({
    required this.isDark,
    required this.bg,
    required this.text,
    required this.muted,
    required this.border,
    required this.card,
    required this.soft,
    required this.accent,
    required this.onAccent,
  });

  static const dark = ReferralPalette._(
    isDark: true,
    bg: DarkColors.bg,
    text: AppColors.white,
    muted: Color(0x7AFFFFFF), // white 48%
    border: Color(0x17FFFFFF), // white 9%
    card: Color(0x0AFFFFFF), // white 4%
    soft: Color(0x0DFFFFFF), // white 5%
    accent: BrandColors.lime,
    onAccent: AppColors.black,
  );

  static const light = ReferralPalette._(
    isDark: false,
    bg: LightColors.background,
    text: AppColors.black,
    muted: Color(0x6B000000), // black 42%
    border: Color(0x14000000), // black 8%
    card: Color(0xEBFFFFFF), // white 92%
    soft: Color(0x0A000000), // black 4%
    accent: BrandColors.purple,
    onAccent: AppColors.white,
  );

  static ReferralPalette of(BuildContext context) =>
      context.colors.isDark ? dark : light;

  final bool isDark;
  final Color bg;
  final Color text;
  final Color muted;
  final Color border;
  final Color card;
  final Color soft;

  /// RN `COLORS.brand.rose`: lime in dark, purple in light.
  final Color accent;
  final Color onAccent;

  /// Refresh button: rose at 35% (border) and 12% (fill).
  Color get accentBorder => accent.withValues(alpha: 0.35);
  Color get accentFill => accent.withValues(alpha: 0.12);
}
