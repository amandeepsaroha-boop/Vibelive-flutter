import 'package:flutter/painting.dart';

/// Port of the RN color system (`constants/Colors.js`). Theme-independent
/// values live here; anything that changes with dark/light mode (e.g. the RN
/// `COLORS.brand.rose` getter) lives in `VibeColors` — use `context.colors`.
abstract final class AppColors {
  // Base
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);
  static const transparent = Color(0x00000000);
  static const red = Color(0xFFFF3B30);
  static const orange = Color(0xFFFF9500);
  static const blue = Color(0xFF2F80ED);
  static const green = Color(0xFF27AE60);
  static const gray = Color(0xFF8E8E93);
  static const slate900 = Color(0xFF111827);
  static const slate500 = Color(0xFF6B7280);
  static const slate200 = Color(0xFFE5E7EB);
  static const slate100 = Color(0xFFF3F4F6);
  static const slate50 = Color(0xFFF9FAFB);

  // Misc brand accents
  static const heart = Color(0xFFFF3D68);
  static const meGreen = Color(0xFF19A786);
  static const bgGrayLight = Color(0xFFF2F2F2);
  static const logoutRed = Color(0xFFFF4B4B);
  static const darkSurface = Color(0xFF12121A);
  static const darkWarningBg = Color(0xF2141419); // rgba(20,20,25,0.95)
  static const navActiveBg = Color(0x2486A5D2); // rgba(134,165,210,0.14)

  /// `whiteRGBA(opacity)` from RN.
  static Color whiteA(double opacity) => white.withValues(alpha: opacity);

  /// `blackRGBA(opacity)` from RN.
  static Color blackA(double opacity) => black.withValues(alpha: opacity);
}

abstract final class BrandColors {
  /// `brand.rose` in light mode (the purple brand color).
  static const purple = Color(0xFF5E17EB);
  static const purpleLight = Color(0xFF8F5EFE);
  static const purpleDark = Color(0xFF3A0CA3);

  /// Launcher icon / notification accent (app.json).
  static const iconPurple = Color(0xFF561DE2);

  /// `brand.lime` — also `brand.rose` in dark mode.
  static const lime = Color(0xFFA8EC4A);
  static const limeLight = Color(0xFFC6F482);
  static const limeAlt = lime;
  static const vibeLime = Color(0xFF79FF3F);

  static const teal = Color(0xFF2DD4BF);
  static const tealDark = Color(0xFF14B8A6);
  static const tealDeep = Color(0xFF041012);
  static const tealDarkest = Color(0xFF115E59);
  static const tealDim = Color(0xFF3FB9B1);

  /// WhatsApp share buttons only.
  static const whatsapp = Color(0xFF25D366);

  /// `darkRose` getter from RN: light / dark.
  static const darkRoseLight = Color(0xFFC2185B);
  static const darkRoseDark = Color(0xFF8ECB3A);

  static Color limeA(double opacity) => lime.withValues(alpha: opacity);
  static Color vibeLimeA(double opacity) => vibeLime.withValues(alpha: opacity);
  static Color purpleA(double opacity) => purple.withValues(alpha: opacity);
}

/// RN `COLORS.dark`.
abstract final class DarkColors {
  static const bg = Color(0xFF050508);
  static const text = Color(0xFFFFFFFF);
  static const border = Color(0x1AFFFFFF); // white 10%
  static const background = Color(0xFF000000);
  static const pureBlack = Color(0xFF000000);
  static const splashBackground = Color(0xFF080808);
  static const surface = Color(0x0AFFFFFF); // white 4%
  static const surfaceDeep = Color(0x05FFFFFF); // white 2%
  static const surfaceVariant = Color(0x0FFFFFFF); // white 6%
  static const borderSubtle = Color(0x0DFFFFFF); // white 5%
  static const borderFocus = Color(0x38A8EC4A); // lime 22%
  static const borderDarkest = Color(0xFF101218);
  static const navBg = Color(0xFF0A0A16);
  static const surfaceSolid = Color(0xFF12121A);
}

/// RN `COLORS.light`.
abstract final class LightColors {
  static const bg = Color(0xFFFFF8F5);
  static const text = Color(0xFF0A0A0A);
  static const border = Color(0x14000000); // black 8%
  static const background = Color(0xFFF4F7FB);
  static const surface = Color(0xE6FFFFFF); // white 90%
  static const muted = Color(0x73000000); // black 45%
  static const navBg = Color(0xFFFFFFFF);
}

/// RN `COLORS.text` (dark-surface typography).
abstract final class TextColors {
  static const primary = Color(0xFFFFFFFF);
  static const secondary = Color(0xEBFFFFFF); // 92%
  static const dim = Color(0x66FFFFFF); // 40%
  static const muted = Color(0x33FFFFFF); // 20%
  static const error = Color(0xFFFF3B30);
  static const errorSubtle = Color(0xFFFCA5A5);
  static const teal = Color(0xFF99F6E4);
}

/// RN `COLORS.danger / warning / info`.
abstract final class StatusColors {
  /// A payment or action that went through (the payment success burst).
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFE6F8EE);
  static const danger = Color(0xFFFF5D7D);
  static const dangerRed = Color(0xFFEF4444);
  static const warning = Color(0xFFFFB020);
  static const warningOrange = Color(0xFFF59E0B);
  static const info = Color(0xFF60A5FA);

  static Color dangerA(double opacity) => danger.withValues(alpha: opacity);
  static Color warningA(double opacity) => warning.withValues(alpha: opacity);
  static Color infoA(double opacity) => info.withValues(alpha: opacity);
}

/// RN `COLORS.hot`.
abstract final class HotColors {
  static const actionBgDark = Color(0xA80A0C12); // rgba(10,12,18,0.66)
  static const profileActionBorderLight = Color(0x730F8458); // 45%
  static const profileActionBgDark = Color(0xC70E1E16); // rgba(14,30,22,0.78)
  static const profileIconLight = Color(0xFF0F8458);
}

/// RN `COLORS.availability`.
abstract final class AvailabilityColors {
  static const vacationPillDark = Color(0x3D768EC0);
  static const vacationPillLight = Color(0xFFEAF0FF);
  static const vacationDot = Color(0xFF3257A8);

  static const availablePillDark = Color(0x3819A786);
  static const availablePillLight = Color(0xFFD9F5EA);
  static const availableDot = Color(0xFF149C76);

  static const customPillDark = Color(0x335A8CCD);
  static const customPillLight = Color(0xFFE6F0FF);
  static const customDot = Color(0xFF3C78D8);
}

/// RN `COLORS.modal`.
abstract final class ModalColors {
  static const backdropDark = Color(0xC7030408); // rgba(3,4,8,0.78)
  static const backdropLight = Color(0x5C0F172A); // rgba(15,23,42,0.36)
  static const cardDark = Color(0xFF111318);
  static const borderDark = Color(0x14FFFFFF);
  static const borderLight = Color(0x140F172A);
  static const textDark = Color(0xFFF8FAFC);
  static const textLight = Color(0xFF111827);
  static const mutedDark = Color(0xA3F1F5F9); // 64%
  static const mutedLight = Color(0x94111827); // 58%
  static const secondaryBgDark = Color(0x0DFFFFFF);
  static const secondaryBgLight = Color(0x0D0F172A);
}

/// RN `COLORS.ai` (Heart Guide / voice widget).
abstract final class AiColors {
  static const violetLight = Color(0xFFA78BFA);
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const pinkLight = Color(0xFFF472B6);
  static const darkPurple = Color(0xFF0F0A1F);
  static const violetDim = Color(0xFFF0E9FF);
  static const slateGray = Color(0xFF6B7280);
  static const greenSuccess = Color(0xFF34D399);
  static const greenSuccessDark = Color(0xFF059669);
  static const pinkDark = Color(0xFFDB2777);
  static const violetDark = Color(0xFF7C3AED);
  static const indigo = Color(0xFF6366F1);
  static const indigoGlow = Color(0x806366F1);
  static const indigoRipple = Color(0x596366F1);
  static const greenSuccessGlow = Color(0x9934D399);
  static const greenSuccessRipple = Color(0x7334D399);
  static const pinkLightGlow = Color(0xB3F472B6);
  static const pinkLightRipple = Color(0x80F472B6);
  static const violetGlow = Color(0x99A78BFA);
  static const violetRipple = Color(0x66A78BFA);
  static const glow = Color(0x80A78BFA);
  static const glow3 = Color(0x4DA78BFA);
  static const deepVoiceBg = [
    Color(0xFF08051A),
    Color(0xFF0D0920),
    Color(0xFF12091E),
  ];
}

/// RN `GRADIENTS` (theme-independent ones; `roseGlow` is on `VibeColors`).
abstract final class AppGradients {
  static const tealBadge = [Color(0x1A14B8A6), Color(0x3314B8A6)];
  static const limeGlow = [Color(0x14A8EC4A), Color(0x00080808)];
  static const splashFade = [Color(0xFF080808), Color(0x00080808)];
  static const blackFade = [Color(0xE0000000), Color(0x00000000)];
}

/// RN `LAYOUT`.
abstract final class AppRadius {
  static const double base = 40;
  static const double large = 55;
}

/// Loading skeletons (`Shimmer` / `SkeletonBox`). Translucent, so they sit on
/// any surface of their theme. Each pair shares one RGB and differs only in
/// alpha: the shimmer modulates the box's alpha, it never recolours it.
abstract final class SkeletonColors {
  /// Dark: white 7 % at rest, white 12 % under the sweep.
  static const darkBase = Color(0x12FFFFFF);
  static const darkHighlight = Color(0x1FFFFFFF);

  /// Light: a light grey (black 7 %), lightening to black 3 % under the sweep.
  static const lightBase = Color(0x12000000);
  static const lightHighlight = Color(0x08000000);
}
