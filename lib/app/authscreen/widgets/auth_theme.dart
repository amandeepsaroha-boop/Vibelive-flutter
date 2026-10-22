import 'package:flutter/widgets.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';

/// Colors of the sign-in flow (RN `authTheme.js`): the login screen, its
/// sheet and its Google / Apple / option buttons.
///
/// The light set follows the login design (white page, navy ink, brand
/// purple, lime accents); the dark set is its counterpart, with the purple
/// lifted so it reads on black. Both are constants: a build never allocates
/// them.
@immutable
class AuthTheme {
  const AuthTheme._({
    required this.dark,
    required this.bg,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.card,
    required this.sheet,
    required this.backdrop,
    required this.cardBorder,
    required this.success,
    required this.successSoft,
  });

  static const darkTheme = AuthTheme._(
    dark: true,
    bg: AppColors.black,
    ink: AppColors.white,
    muted: Color(0x9EFFFFFF), // white 62%
    faint: Color(0x59FFFFFF), // white 35%
    line: Color(0x1FFFFFFF), // white 12%
    accent: Color(0xFFA27BFF),
    accentSoft: Color(0x24A27BFF), // 14%
    accentBorder: Color(0x4DA27BFF), // 30%
    card: Color(0x0DFFFFFF), // white 5%
    sheet: Color(0xFF121019),
    backdrop: Color(0xB8000000), // black 72%
    cardBorder: Color(0x29FFFFFF), // white 16%
    success: BrandColors.vibeLime,
    successSoft: Color(0x2979FF3F), // vibe lime 16%
  );

  static const lightTheme = AuthTheme._(
    dark: false,
    bg: Color(0xFFFCFCFF),
    ink: Color(0xFF110D2E),
    muted: Color(0xFF6B6E82),
    faint: Color(0x61110D2E), // ink 38%
    line: Color(0x1F110D2E), // ink 12%
    accent: BrandColors.purple,
    accentSoft: Color(0x0F5E17EB), // 6%
    accentBorder: Color(0x295E17EB), // 16%
    card: AppColors.white,
    sheet: AppColors.white,
    backdrop: Color(0x6B110D2E), // ink 42%
    cardBorder: Color(0x24110D2E), // ink 14%
    success: AppColors.green,
    successSoft: Color(0x1A27AE60), // 10%
  );

  /// Follows the app theme (system by default), like RN `useAuthTheme`.
  static AuthTheme of(BuildContext context) =>
      context.colors.isDark ? darkTheme : lightTheme;

  final bool dark;
  final Color bg, ink, muted, faint, line;
  final Color accent, accentSoft, accentBorder;
  final Color card, sheet, backdrop, cardBorder;
  final Color success, successSoft;

  /// Same in both themes.
  Color get lime => BrandColors.lime;
  Color get primary => BrandColors.purple;
  Color get primaryText => AppColors.white;
  Color get danger => AppColors.red;

  /// RN text style: [size], [height] (line height) and [spacing] in design
  /// px, scaled.
  static TextStyle text(
    double size, {
    required Color color,
    FontWeight weight = FontWeight.w500,
    double? height,
    double spacing = 0,
  }) => TextStyle(
    fontSize: size.ms,
    fontWeight: weight,
    color: color,
    height: height == null ? null : height / size,
    letterSpacing: spacing.ms,
  );
}

/// Text in the sign-in design: never scaled by the OS font size (RN
/// `allowFontScaling={false}`).
class AuthText extends StatelessWidget {
  const AuthText.rich(
    this.span, {
    super.key,
    this.align = TextAlign.center,
    this.maxLines,
  });

  final InlineSpan span;
  final TextAlign align;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text.rich(
    span,
    textAlign: align,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    textScaler: TextScaler.noScaling,
  );
}
