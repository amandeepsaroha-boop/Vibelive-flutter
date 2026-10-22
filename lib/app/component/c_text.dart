import 'package:flutter/widgets.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';

/// RN `CFont` variants.
enum CTextVariant { h1, h2, sub, caption, body }

/// App text (RN `CFont`): never scaled by the OS font-size setting, sizes go
/// through `moderateScale`, and the text is an **i18n key** by default.
///
/// ```dart
/// CText('home:title', variant: CTextVariant.h1)
/// CText('greeting', variables: {'name': name})
/// CText.raw(expert.name)          // data from the server: not translated
/// ```
class CText extends StatelessWidget {
  const CText(
    this.text, {
    super.key,
    this.variant = CTextVariant.body,
    this.variables,
    this.count,
    this.color,
    this.size,
    this.weight,
    this.italic = false,
    this.letterSpacing,
    this.height,
    this.uppercase,
    this.align,
    this.maxLines,
    this.overflow,
    this.style,
  }) : translate = true;

  /// Literal text (names, server messages, numbers).
  const CText.raw(
    this.text, {
    super.key,
    this.variant = CTextVariant.body,
    this.color,
    this.size,
    this.weight,
    this.italic = false,
    this.letterSpacing,
    this.height,
    this.uppercase,
    this.align,
    this.maxLines,
    this.overflow,
    this.style,
  }) : translate = false,
       variables = null,
       count = null;

  final String text;
  final bool translate;
  final CTextVariant variant;
  final Map<String, dynamic>? variables;
  final int? count;

  /// Defaults to the theme text color.
  final Color? color;

  /// Unscaled size; `moderateScale` is applied here.
  final double? size;
  final FontWeight? weight;
  final bool italic;
  final double? letterSpacing;

  /// Line height in logical px (like RN `lineHeight`), scaled.
  final double? height;

  /// Overrides the variant's uppercase rule.
  final bool? uppercase;
  final TextAlign? align;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Merged last.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final spec = _specs[variant]!;
    final base = color ?? context.colors.text;
    final fontSize = moderateScale(size ?? spec.size);
    var value = translate
        ? context.t(text, variables: variables, count: count)
        : text;
    if (uppercase ?? spec.uppercase) value = value.toUpperCase();

    final textStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: weight ?? spec.weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: moderateScale(letterSpacing ?? spec.letterSpacing),
      height: height == null ? null : moderateScale(height!) / fontSize,
      color: spec.opacity == 1
          ? base
          : base.withValues(alpha: base.a * spec.opacity),
    ).merge(style);

    return Text(
      value,
      style: textStyle,
      textAlign: align,
      maxLines: maxLines,
      overflow: overflow ?? (maxLines != null ? TextOverflow.ellipsis : null),
      textScaler: TextScaler.noScaling,
    );
  }
}

class _Spec {
  const _Spec(
    this.size,
    this.weight, {
    this.letterSpacing = 0,
    this.uppercase = false,
    this.opacity = 1,
  });

  final double size;
  final FontWeight weight;
  final double letterSpacing;
  final bool uppercase;
  final double opacity;
}

const _specs = {
  CTextVariant.h1: _Spec(
    38,
    FontWeight.w900,
    letterSpacing: -1,
    uppercase: true,
  ),
  CTextVariant.h2: _Spec(24, FontWeight.w800, letterSpacing: -0.5),
  CTextVariant.sub: _Spec(
    14,
    FontWeight.w900,
    letterSpacing: 2.5,
    uppercase: true,
    opacity: 0.8,
  ),
  CTextVariant.caption: _Spec(
    10,
    FontWeight.w800,
    letterSpacing: 2,
    uppercase: true,
    opacity: 0.6,
  ),
  CTextVariant.body: _Spec(16, FontWeight.w600),
};
