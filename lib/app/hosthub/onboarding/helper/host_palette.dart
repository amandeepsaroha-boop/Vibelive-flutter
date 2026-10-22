import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';

/// Colors of the host flow and the host's first-steps panel, derived from
/// the app theme (`VibeColors` + `AppColors` / `StatusColors`), so the flow
/// follows the app in both modes (purple accent in light, lime in dark).
/// The flow is flat: nothing here casts a shadow. One instance per mode.
@immutable
class HostPalette {
  const HostPalette._({
    required this.isDark,
    required this.accent,
    required this.onAccent,
    required this.gradient,
    required this.text,
    required this.muted,
    required this.faint,
    required this.bg,
    required this.card,
    required this.cardBorder,
    required this.field,
    required this.fieldBorder,
    required this.tint,
    required this.tintBorder,
    required this.soft,
    required this.neutral,
    required this.track,
    required this.success,
    required this.successTint,
    required this.danger,
    required this.dangerTint,
    required this.warning,
    required this.warningTint,
  });

  factory HostPalette._from(VibeColors c) => HostPalette._(
    isDark: c.isDark,
    accent: c.accent,
    onAccent: c.onAccent,
    gradient: c.primaryGradient,
    text: c.text,
    muted: c.textMuted,
    faint: c.textMuted.withValues(alpha: c.textMuted.a * 0.75),
    bg: c.bg,
    card: c.surface,
    cardBorder: c.border,
    field: c.surface,
    fieldBorder: c.border,
    tint: c.accentA(0.08),
    tintBorder: c.accentA(0.22),
    soft: c.accentA(0.05),
    neutral: c.surfaceVariant,
    track: c.border,
    success: AppColors.green,
    successTint: AppColors.green.withValues(alpha: 0.1),
    danger: StatusColors.dangerRed,
    dangerTint: StatusColors.dangerRed.withValues(alpha: 0.08),
    warning: StatusColors.warningOrange,
    warningTint: StatusColors.warningOrange.withValues(alpha: 0.1),
  );

  static final light = HostPalette._from(VibeColors.light);
  static final dark = HostPalette._from(VibeColors.dark);

  static HostPalette of(BuildContext context) =>
      context.colors.isDark ? dark : light;

  final bool isDark;
  final Color accent;
  final Color onAccent;

  /// Buttons, selected chips, switches, the progress bar.
  final List<Color> gradient;
  final Color text;
  final Color muted;

  /// Placeholders, disabled labels.
  final Color faint;
  final Color bg;
  final Color card;
  final Color cardBorder;
  final Color field;
  final Color fieldBorder;

  /// Lavender fill (language chips, tips, info, search, back chevron).
  final Color tint;
  final Color tintBorder;

  /// Lighter lavender (suggestion panel, guidelines card).
  final Color soft;

  /// Neutral grey fill (schedule rows, rate stepper).
  final Color neutral;

  /// Progress bar and the off switch.
  final Color track;
  final Color success;
  final Color successTint;
  final Color danger;
  final Color dangerTint;
  final Color warning;
  final Color warningTint;

  LinearGradient get buttonGradient => LinearGradient(
    colors: gradient,
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
