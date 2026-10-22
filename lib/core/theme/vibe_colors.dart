import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Colors that differ between dark and light mode.
/// Read them with `context.colors` (one lookup, rebuilds on theme change).
@immutable
class VibeColors extends ThemeExtension<VibeColors> {
  const VibeColors({
    required this.isDark,
    required this.accent,
    required this.onAccent,
    required this.contrast,
    required this.inverse,
    required this.darkRose,
    required this.bg,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.navBg,
    required this.warnBarBg,
    required this.modalBackdrop,
    required this.modalCard,
    required this.modalBorder,
    required this.modalText,
    required this.modalMuted,
    required this.modalSecondaryBg,
    required this.primaryGradient,
    required this.secondaryGradient,
    required this.roseGlow,
  });

  final bool isDark;

  /// RN `COLORS.brand.rose`: lime in dark, purple in light.
  final Color accent;

  /// Text/icon color on top of [accent].
  final Color onAccent;

  /// RN `brand.whitemode`: white in dark, black in light.
  final Color contrast;

  /// RN `brand.opowhite`: black in dark, white in light.
  final Color inverse;

  /// RN `COLORS.darkRose`.
  final Color darkRose;

  /// Screen background (RN `dark.bg` / `light.bg`).
  final Color bg;

  /// `VibeBackground` fill.
  final Color background;

  final Color surface;
  final Color surfaceVariant;
  final Color text;
  final Color textMuted;
  final Color border;
  final Color navBg;
  final Color warnBarBg;

  final Color modalBackdrop;
  final Color modalCard;
  final Color modalBorder;
  final Color modalText;
  final Color modalMuted;
  final Color modalSecondaryBg;

  /// `Button` primary gradient.
  final List<Color> primaryGradient;

  /// `Button` secondary gradient.
  final List<Color> secondaryGradient;

  /// RN `GRADIENTS.roseGlow`.
  final List<Color> roseGlow;

  /// RN `brand.roseRGBA(opacity)`.
  Color accentA(double opacity) => accent.withValues(alpha: opacity);

  static const dark = VibeColors(
    isDark: true,
    accent: BrandColors.lime,
    onAccent: AppColors.black,
    contrast: AppColors.white,
    inverse: AppColors.black,
    darkRose: BrandColors.darkRoseDark,
    bg: DarkColors.bg,
    background: AppColors.black,
    surface: DarkColors.surface,
    surfaceVariant: DarkColors.surfaceVariant,
    text: DarkColors.text,
    textMuted: TextColors.dim,
    border: DarkColors.border,
    navBg: DarkColors.navBg,
    warnBarBg: AppColors.darkWarningBg,
    modalBackdrop: ModalColors.backdropDark,
    modalCard: ModalColors.cardDark,
    modalBorder: ModalColors.borderDark,
    modalText: ModalColors.textDark,
    modalMuted: ModalColors.mutedDark,
    modalSecondaryBg: ModalColors.secondaryBgDark,
    primaryGradient: [BrandColors.lime, BrandColors.limeLight],
    secondaryGradient: [BrandColors.purple, BrandColors.purpleLight],
    roseGlow: [Color(0x1AA8EC4A), Color(0x00A8EC4A)],
  );

  static const light = VibeColors(
    isDark: false,
    accent: BrandColors.purple,
    onAccent: AppColors.white,
    contrast: AppColors.black,
    inverse: AppColors.white,
    darkRose: BrandColors.darkRoseLight,
    bg: LightColors.bg,
    background: LightColors.background,
    surface: LightColors.surface,
    surfaceVariant: AppColors.slate100,
    text: LightColors.text,
    textMuted: LightColors.muted,
    border: LightColors.border,
    navBg: LightColors.navBg,
    warnBarBg: AppColors.white,
    modalBackdrop: ModalColors.backdropLight,
    modalCard: AppColors.white,
    modalBorder: ModalColors.borderLight,
    modalText: ModalColors.textLight,
    modalMuted: ModalColors.mutedLight,
    modalSecondaryBg: ModalColors.secondaryBgLight,
    primaryGradient: [BrandColors.purple, BrandColors.purpleLight],
    secondaryGradient: [BrandColors.lime, BrandColors.limeLight],
    roseGlow: [Color(0x1A5E17EB), Color(0x005E17EB)],
  );

  @override
  VibeColors copyWith() => this;

  @override
  VibeColors lerp(VibeColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension VibeColorsContext on BuildContext {
  VibeColors get colors =>
      Theme.of(this).extension<VibeColors>() ?? VibeColors.dark;
}

/// Skeleton tokens of the current theme (`SkeletonColors`).
extension VibeSkeletonColors on VibeColors {
  /// Resting fill of a skeleton block.
  Color get skeletonBase =>
      isDark ? SkeletonColors.darkBase : SkeletonColors.lightBase;

  /// Fill under the shimmer sweep.
  Color get skeletonHighlight =>
      isDark ? SkeletonColors.darkHighlight : SkeletonColors.lightHighlight;
}
