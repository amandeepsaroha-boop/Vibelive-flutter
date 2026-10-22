import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';

/// Theme colors of the splash and onboarding (RN `makeSplashPalette`). The
/// dark set is the original look, value for value; the light set follows
/// the app theme (system by default) with brand purple as the accent, since
/// lime is unreadable on white. Both are constants.
@immutable
class SplashPalette {
  const SplashPalette._({
    required this.dark,
    required this.bg,
    required this.text,
    required this.desc,
    required this.muted,
    required this.glow,
    required this.accent,
    required this.track,
    required this.progressTrack,
    required this.dot,
    required this.chipBg,
    required this.chipBorder,
    required this.chipText,
    required this.ping,
    required this.cardBg,
    required this.cardBorder,
    required this.liveGlow,
    required this.shellBg,
    required this.shellBorder,
    required this.inner,
    required this.onAccent,
    this.ctaBg,
    this.ctaText,
  });

  static const darkPalette = SplashPalette._(
    dark: true,
    bg: DarkColors.splashBackground,
    text: TextColors.primary,
    desc: TextColors.dim,
    muted: TextColors.muted,
    glow: Color(0x147CFF01),
    accent: BrandColors.lime,
    track: Color(0x1FFFFFFF), // white 12%
    progressTrack: DarkColors.border,
    dot: Color(0x40FFFFFF), // white 25%
    chipBg: Color(0x0FFFFFFF), // white 6%
    chipBorder: Color(0x14FFFFFF), // white 8%
    chipText: Color(0xA6FFFFFF), // white 65%
    ping: Color(0x247CFF01), // glow green 14%
    cardBg: DarkColors.surface,
    cardBorder: Color(0x24FFFFFF), // white 14%
    liveGlow: Color(0x297CFF01), // glow green 16%
    shellBg: DarkColors.borderDarkest,
    shellBorder: Color(0x24FFFFFF),
    inner: AppColors.darkSurface,
    onAccent: AppColors.black,
  );

  static const lightPalette = SplashPalette._(
    dark: false,
    bg: AppColors.white,
    text: LightColors.text,
    desc: Color(0x80000000), // black 50%
    muted: Color(0x66000000), // black 40%
    glow: Color(0x125E17EB), // purple 7%
    accent: BrandColors.purple,
    track: Color(0x14000000), // black 8%
    progressTrack: Color(0x14000000),
    dot: Color(0x2E000000), // black 18%
    chipBg: Color(0x0A000000), // black 4%
    chipBorder: Color(0x0F000000), // black 6%
    chipText: Color(0xB3000000), // black 70%
    ping: Color(0x1F5E17EB), // purple 12%
    cardBg: AppColors.slate50,
    cardBorder: Color(0x14000000),
    liveGlow: Color(0x1F5E17EB),
    shellBg: AppColors.white,
    shellBorder: Color(0x14000000),
    inner: AppColors.slate100,
    onAccent: AppColors.white,
    // The CTA is white on dark; its light default (slate100) vanishes on
    // white.
    ctaBg: BrandColors.purple,
    ctaText: AppColors.white,
  );

  static SplashPalette of(BuildContext context) =>
      context.colors.isDark ? darkPalette : lightPalette;

  final bool dark;
  final Color bg, text, desc, muted;

  /// Top glow; it fades to transparent.
  final Color glow;
  final Color accent, track, progressTrack, dot;
  final Color chipBg, chipBorder, chipText;
  final Color ping, cardBg, cardBorder, liveGlow;
  final Color shellBg, shellBorder, inner;

  /// Marks and text drawn on an [accent] fill.
  final Color onAccent;

  /// Onboarding CTA overrides; null keeps the button's own colors.
  final Color? ctaBg, ctaText;

  /// [bg] with no opacity, for the fades into it.
  Color get bgClear => bg.withValues(alpha: 0);

  Color get glowEnd =>
      dark ? const Color(0x00080808) : glow.withValues(alpha: 0);

  SystemUiOverlayStyle get overlay => SystemUiOverlayStyle(
    statusBarColor: AppColors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: bg,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
  );
}
