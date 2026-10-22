import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// RN FavouritesScreen `theme` memo.
@immutable
class FavouritesPalette {
  const FavouritesPalette._({
    required this.text,
    required this.muted,
    required this.border,
    required this.card,
    required this.soft,
  });

  static const dark = FavouritesPalette._(
    text: AppColors.white,
    muted: Color(0x7AFFFFFF), // white 48%
    border: Color(0x17FFFFFF), // white 9%
    card: Color(0x0AFFFFFF), // white 4%
    soft: Color(0x0DFFFFFF), // white 5%
  );

  static const light = FavouritesPalette._(
    text: AppColors.black,
    muted: Color(0x6B000000), // black 42%
    border: Color(0x14000000), // black 8%
    card: Color(0xEBFFFFFF), // white 92%
    soft: Color(0x0A000000), // black 4%
  );

  static FavouritesPalette of(BuildContext context) =>
      context.colors.isDark ? dark : light;

  final Color text;
  final Color muted;
  final Color border;
  final Color card;
  final Color soft;
}
