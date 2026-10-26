import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// RN WalletScreen / TransferModal `theme` object, per mode.
@immutable
class WalletPalette {
  const WalletPalette._({
    required this.dark,
    required this.bg,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.cardBg,
    required this.cardBorder,
    required this.inputBg,
    required this.inputBorder,
    required this.accent,
    required this.onAccent,
    required this.soft,
  });

  static const _dark = WalletPalette._(
    dark: true,
    bg: DarkColors.bg,
    text: DarkColors.text,
    muted: Color(0x7AFFFFFF), // white 48%
    subtle: Color(0x52FFFFFF), // white 32%
    cardBg: DarkColors.surface,
    cardBorder: DarkColors.border,
    inputBg: DarkColors.surfaceVariant,
    inputBorder: DarkColors.border,
    accent: BrandColors.lime,
    onAccent: AppColors.black,
    soft: Color(0x0AFFFFFF), // white 4%
  );

  static const _light = WalletPalette._(
    dark: false,
    bg: LightColors.background,
    text: LightColors.text,
    muted: Color(0x6B000000), // black 42%
    subtle: Color(0x52000000), // black 32%
    cardBg: AppColors.white,
    cardBorder: LightColors.border,
    inputBg: AppColors.slate100,
    inputBorder: AppColors.slate200,
    accent: BrandColors.purple,
    onAccent: AppColors.white,
    soft: Color(0x08000000), // black 3%
  );

  static WalletPalette of(BuildContext context) =>
      context.colors.isDark ? _dark : _light;

  final bool dark;

  /// Filled accent surfaces (pills, badges, offer cards): purple → deep
  /// purple in light, lime → deeper lime in dark. Text on it: [onAccent].
  List<Color> get accentGradient => dark
      ? const [BrandColors.lime, BrandColors.limeLight]
      : const [BrandColors.purple, BrandColors.purpleDark];

  /// Screen and modal background.
  final Color bg;
  final Color text;
  final Color muted;
  final Color subtle;
  final Color cardBg;
  final Color cardBorder;
  final Color inputBg;
  final Color inputBorder;

  /// RN `COLORS.brand.rose`: lime in dark, purple in light.
  final Color accent;
  final Color onAccent;
  final Color soft;

  /// Wallet credit / debit (RN `COLORS.green`, `COLORS.text.error`).
  static const success = AppColors.green;
  static const error = TextColors.error;
  static const pending = StatusColors.warning;

  /// Credit / debit icon tiles (RN literals).
  static const creditTile = Color(0x1F00C853); // rgba(0,200,83,.12)
  static const debitTile = Color(0x1FFF4D4F); // rgba(255,77,79,.12)

  /// Selected add-money preset (RN literal rgba(255,0,128,.12)).
  static const presetSelectedBg = Color(0x1FFF0080);
}
