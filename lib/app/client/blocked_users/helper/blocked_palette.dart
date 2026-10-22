import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// RN BlockedUsersScreen `theme` memo.
@immutable
class BlockedPalette {
  const BlockedPalette._({
    required this.isDark,
    required this.text,
    required this.muted,
    required this.border,
    required this.card,
    required this.cardBorder,
    required this.backBg,
  });

  static const dark = BlockedPalette._(
    isDark: true,
    text: AppColors.white,
    muted: Color(0x7AFFFFFF), // white 48%
    border: Color(0x17FFFFFF), // white 9%
    card: Color(0x0AFFFFFF), // white 4%
    cardBorder: Color(0x14FFFFFF), // white 8%
    backBg: Color(0x14FFFFFF), // white 8%
  );

  static const light = BlockedPalette._(
    isDark: false,
    text: AppColors.black,
    muted: Color(0x73000000), // black 45%
    border: Color(0x14000000), // black 8%
    card: Color(0xEBFFFFFF), // white 92%
    cardBorder: Color(0x0F000000), // black 6%
    backBg: Color(0x0A000000), // black 4%
  );

  static BlockedPalette of(BuildContext context) =>
      context.colors.isDark ? dark : light;

  final bool isDark;
  final Color text;
  final Color muted;
  final Color border;
  final Color card;
  final Color cardBorder;

  /// Round back button.
  final Color backBg;
}
