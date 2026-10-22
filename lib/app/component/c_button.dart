import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import 'c_text.dart';
import 'pressable.dart';

/// RN `Button` variants.
enum CButtonVariant { primary, secondary, outline, ghost, small, cta }

/// App button (RN `Button`). [title] is an i18n key.
///
/// Taps are debounced (600 ms) so a double tap can't fire an API call twice.
class CButton extends StatefulWidget {
  const CButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.variant = CButtonVariant.primary,
    this.titleVariables,
    this.translate = true,
    this.loading = false,
    this.disabled = false,
    this.icon,
    this.showArrow = true,
    this.arrowBorder = false,
    this.arrowIcon,
    this.titleColor,
    this.color,
    this.titleSize,
    this.height,
    this.width,
    this.debounce = const Duration(milliseconds: 600),
  });

  final String title;
  final Map<String, dynamic>? titleVariables;

  /// false = [title] is literal text.
  final bool translate;
  final VoidCallback? onPressed;
  final CButtonVariant variant;
  final bool loading;
  final bool disabled;

  /// Leading widget.
  final Widget? icon;
  final bool showArrow;
  final bool arrowBorder;

  /// Replaces the default arrow.
  final IconData? arrowIcon;
  final Color? titleColor;

  /// Background override (no gradient); e.g. the purple onboarding CTA on
  /// the light theme.
  final Color? color;

  /// Unscaled label size (defaults per variant).
  final double? titleSize;
  final double? height;
  final double? width;
  final Duration debounce;

  @override
  State<CButton> createState() => _CButtonState();
}

class _CButtonState extends State<CButton> {
  DateTime _lastPress = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _inactive =>
      widget.onPressed == null || widget.disabled || widget.loading;

  void _handlePress() {
    if (_inactive) return;
    final now = clock.now(); // fake-able in tests
    if (now.difference(_lastPress) < widget.debounce) return;
    _lastPress = now;
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.variant;
    final isCta = v == CButtonVariant.cta;
    final isGhost = v == CButtonVariant.ghost;

    final gradient = widget.color != null
        ? null
        : switch (v) {
            CButtonVariant.primary => c.primaryGradient,
            CButtonVariant.secondary => c.secondaryGradient,
            _ => null,
          };
    final fg =
        widget.titleColor ??
        switch (v) {
          CButtonVariant.primary => c.onAccent,
          CButtonVariant.secondary => c.contrast,
          CButtonVariant.ghost => c.textMuted,
          CButtonVariant.cta => DarkColors.splashBackground,
          _ => c.text,
        };
    final arrowColor = isCta ? BrandColors.lime : fg;
    final radius = isCta ? 999.0 : 24.ms;

    final label = widget.translate
        ? CText(
            widget.title,
            variables: widget.titleVariables,
            color: fg,
            size: widget.titleSize ?? (isCta ? 28 : (isGhost ? 11 : 14)),
            weight: FontWeight.w900,
            letterSpacing: isCta ? 0 : 2,
            italic: isCta,
            uppercase: !isCta,
            maxLines: 1,
            height: isCta && widget.titleSize == null ? 32 : null,
          )
        : CText.raw(
            widget.title,
            color: fg,
            size: widget.titleSize ?? (isCta ? 28 : (isGhost ? 11 : 14)),
            weight: FontWeight.w900,
            letterSpacing: isCta ? 0 : 2,
            italic: isCta,
            uppercase: !isCta,
            maxLines: 1,
          );

    final Widget content = widget.loading
        ? SizedBox.square(
            dimension: 20,
            child: RepaintBoundary(
              child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: v == CButtonVariant.small
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                widget.icon!,
                SizedBox(width: 10.ms),
              ],
              if (isCta)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 28.ms),
                    child: label,
                  ),
                )
              else
                Flexible(child: label),
              if (widget.showArrow || widget.arrowIcon != null)
                _Arrow(
                  color: arrowColor,
                  icon: widget.arrowIcon,
                  bordered: widget.arrowBorder,
                  cta: isCta,
                ),
            ],
          );

    final decoration = BoxDecoration(
      gradient: gradient == null
          ? null
          : LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      color:
          widget.color ??
          switch (v) {
            CButtonVariant.cta =>
              c.isDark ? AppColors.white : AppColors.slate100,
            _ => null,
          },
      borderRadius: BorderRadius.circular(radius),
      border: v == CButtonVariant.outline
          ? Border.all(color: c.border, width: 1.5)
          : null,
      boxShadow: isCta
          ? [
              BoxShadow(
                color: AppColors.blackA(0.15),
                blurRadius: 12.ms,
                offset: Offset(0, 6.ms),
              ),
            ]
          : null,
    );

    return Opacity(
      opacity: widget.disabled || widget.loading ? 0.5 : 1,
      child: Pressable(
        onPressed: _inactive ? null : _handlePress,
        activeOpacity: 0.8,
        child: Container(
          width: widget.width ?? (isGhost ? null : double.infinity),
          height: isGhost ? null : (widget.height ?? (isCta ? 76.ms : 58.ms)),
          padding: EdgeInsets.symmetric(
            horizontal: isCta ? 12.ms : 16.ms,
            vertical: isGhost ? 12.ms : 0,
          ),
          alignment: isGhost ? null : Alignment.center,
          decoration: decoration,
          child: content,
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.color,
    required this.icon,
    required this.bordered,
    required this.cta,
  });

  final Color color;
  final IconData? icon;
  final bool bordered;
  final bool cta;

  @override
  Widget build(BuildContext context) {
    Widget glyph(double iconSize) => icon != null
        ? Icon(icon, size: iconSize, color: color)
        : CustomPaint(
            size: const Size.square(22),
            painter: _ArrowPainter(color),
          );

    if (cta) {
      return Container(
        width: 48.ms,
        height: 48.ms,
        margin: EdgeInsets.only(left: 12.ms),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.black,
          shape: BoxShape.circle,
        ),
        child: glyph(22),
      );
    }
    if (bordered) {
      return Container(
        width: 32.ms,
        height: 32.ms,
        margin: EdgeInsets.only(left: 14.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.whiteA(0.08),
          borderRadius: BorderRadius.circular(10.ms),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: glyph(14),
      );
    }
    return Padding(
      padding: EdgeInsets.only(left: 8.ms),
      child: glyph(18),
    );
  }
}

/// RN `DefaultArrow` SVG: `M3 10h8V6l10 6-10 6v-4H3z` in a 24 viewBox.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final path = Path()
      ..moveTo(3 * s, 10 * s)
      ..lineTo(11 * s, 10 * s)
      ..lineTo(11 * s, 6 * s)
      ..lineTo(21 * s, 12 * s)
      ..lineTo(11 * s, 18 * s)
      ..lineTo(11 * s, 14 * s)
      ..lineTo(3 * s, 14 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}
