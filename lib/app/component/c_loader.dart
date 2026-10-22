import 'package:flutter/material.dart';

import '../../core/theme/vibe_colors.dart';

/// Brand-colored spinner, centered.
class CLoader extends StatelessWidget {
  const CLoader({
    super.key,
    this.size = 28,
    this.color,
    this.strokeWidth = 2.6,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CircularProgressIndicator(
            strokeWidth: strokeWidth,
            color: color ?? context.colors.accent,
          ),
        ),
      ),
    );
  }
}
