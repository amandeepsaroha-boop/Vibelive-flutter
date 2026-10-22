import 'package:flutter/widgets.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';

/// Colors of the Resources screens (RN `theme` memos of DynamicPageScreen,
/// CategoryMenuScreen and CategoriesScreen). One const per mode.
@immutable
class ResourcePalette {
  const ResourcePalette._({
    required this.isDark,
    required this.text,
    required this.muted,
    required this.menuMuted,
    required this.border,
    required this.card,
    required this.soft,
    required this.menuCard,
    required this.menuBorder,
  });

  static const dark = ResourcePalette._(
    isDark: true,
    text: AppColors.white,
    muted: Color(0x7AFFFFFF), // white 48%
    menuMuted: TextColors.dim,
    border: Color(0x17FFFFFF), // white 9%
    card: DarkColors.surface,
    soft: DarkColors.borderSubtle,
    menuCard: DarkColors.surface,
    menuBorder: DarkColors.border,
  );

  static const light = ResourcePalette._(
    isDark: false,
    text: LightColors.text,
    muted: Color(0x6B000000), // black 42%
    menuMuted: LightColors.muted,
    border: LightColors.border,
    card: Color(0xEBFFFFFF), // white 92%
    soft: Color(0x0A000000), // black 4%
    menuCard: Color(0xE6FFFFFF), // white 90%
    menuBorder: LightColors.border,
  );

  static ResourcePalette of(BuildContext context) =>
      context.colors.isDark ? dark : light;

  final bool isDark;
  final Color text;

  /// Page screens (DynamicPage, Categories).
  final Color muted;

  /// Category menu.
  final Color menuMuted;
  final Color border;

  /// Page content card.
  final Color card;

  /// Header buttons, search box.
  final Color soft;

  /// Category menu rows.
  final Color menuCard;
  final Color menuBorder;

  /// RN `COLORS.info.accent`: links.
  static const link = StatusColors.info;

  /// RESOURCES category (`menu-data.js`).
  static const resources = Color(0xFF4E63BF);
}
