import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';

/// Skeleton colors of the current theme, as the boxes and the sweep use them.
///
/// The boxes paint [fill] themselves (the stronger of the theme's base and
/// highlight), so a box is theme-colored even without a [Shimmer]. The sweep
/// only scales the box's alpha (`BlendMode.dstIn`): [rest] of [fill] gives
/// the base color, [peak] the highlight. It never recolours, so a box can
/// never come out white on a dark screen.
@immutable
class SkeletonPalette {
  const SkeletonPalette._(this.fill, this.rest, this.peak);

  factory SkeletonPalette.of(BuildContext context) {
    final c = context.colors;
    final base = c.skeletonBase;
    final highlight = c.skeletonHighlight;
    final fill = base.a >= highlight.a ? base : highlight;
    return SkeletonPalette._(fill, base.a / fill.a, highlight.a / fill.a);
  }

  /// What a [SkeletonBox] paints.
  final Color fill;

  /// Sweep alpha at rest (0–1), giving the theme's base color.
  final double rest;

  /// Sweep alpha at its peak (0–1), giving the theme's highlight color.
  final double peak;
}

/// Shimmer sweep over a static skeleton layout.
///
/// One animated gradient for the whole subtree: the boxes themselves never
/// rebuild or repaint, only the shader moves (GPU), so a full-screen
/// skeleton costs about as much as one box.
///
/// ```dart
/// Shimmer(child: Column(children: [SkeletonBox(height: 270.ms), …]))
/// ```
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SkeletonPalette.of(context);
    final rest = AppColors.blackA(p.rest);
    final peak = AppColors.blackA(p.peak);
    // The sweep repaints the mask on every frame: the outer boundary keeps
    // that from repainting the screen around it (a header, the page). The
    // inner one caches the static boxes; the mask still composites over its
    // layer, so neither boundary changes what is painted.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        child: RepaintBoundary(child: widget.child),
        builder: (_, child) => ShaderMask(
          // Keeps the boxes' own (theme) color and scales only their alpha.
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: [rest, peak, rest],
            stops: const [0.35, 0.5, 0.65],
            begin: const Alignment(-1, -0.3),
            end: const Alignment(1, 0.3),
            transform: _Slide(_ctrl.value),
          ).createShader(bounds),
          child: child,
        ),
      ),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// A placeholder block in the theme's skeleton color. Put it under a
/// [Shimmer] for the sweep; on its own it is a static block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 12,
    this.circle = false,
  });

  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Theme color; the Shimmer only modulates its alpha.
        color: SkeletonPalette.of(context).fill,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Lines of text-shaped skeletons (last one shorter).
class SkeletonLines extends StatelessWidget {
  const SkeletonLines({
    super.key,
    this.lines = 2,
    this.height = 12,
    this.gap = 8,
    this.lastWidthFactor = 0.6,
  });

  final int lines;
  final double height;
  final double gap;
  final double lastWidthFactor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines; i++) ...[
          if (i > 0) SizedBox(height: gap),
          FractionallySizedBox(
            widthFactor: i == lines - 1 && lines > 1 ? lastWidthFactor : 1,
            child: SkeletonBox(height: height, radius: height / 2),
          ),
        ],
      ],
    );
  }
}
