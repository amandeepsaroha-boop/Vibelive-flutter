import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// RN GstDetailsScreen `theme` memo.
@immutable
class GstPalette {
  const GstPalette._({
    required this.bg,
    required this.text,
    required this.muted,
    required this.border,
    required this.card,
    required this.soft,
  });

  static const dark = GstPalette._(
    bg: DarkColors.bg,
    text: DarkColors.text,
    muted: Color(0x7AFFFFFF), // white 48%
    border: DarkColors.border,
    card: DarkColors.surface,
    soft: Color(0x0DFFFFFF), // white 5%
  );

  static const light = GstPalette._(
    bg: LightColors.background,
    text: LightColors.text,
    muted: LightColors.muted,
    border: LightColors.border,
    card: LightColors.surface,
    soft: Color(0x0A000000), // black 4%
  );

  static GstPalette of(BuildContext context) =>
      context.colors.isDark ? dark : light;

  final Color bg;
  final Color text;
  final Color muted;
  final Color border;
  final Color card;

  /// Read-only fields, header buttons.
  final Color soft;
}
