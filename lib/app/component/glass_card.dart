import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';

/// RN `GlassCard`: blurred, translucent card (Vibe_OS v2).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.blur = 15,
    this.radius = AppRadius.base,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.isDark ? DarkColors.surface : LightColors.surface,
            borderRadius: shape,
            border: Border.all(color: c.border),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
