import 'package:flutter/widgets.dart';

import '../../../core/utils/scale.dart';

// Hand-drawn accents of the login design (RN `AuthDecorations`). Purely
// decorative: hidden from screen readers and never in the way of a touch.

/// Three short strokes bursting off the headline.
class Spark extends StatelessWidget {
  const Spark({super.key, required this.color, this.size});

  final Color color;

  /// Width; defaults to 36 (scaled). Height is 1.25 × width.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final w = size ?? 36.ms;
    return _Decoration(size: Size(w, w * 1.25), painter: _SparkPainter(color));
  }
}

/// Loose wave. [weight] thickens it (the lime one in the corner is heavier).
class Squiggle extends StatelessWidget {
  const Squiggle({super.key, required this.color, this.width, this.weight = 6});

  final Color color;

  /// Defaults to 50 (scaled). Height is half the width.
  final double? width;
  final double weight;

  @override
  Widget build(BuildContext context) {
    final w = width ?? 50.ms;
    return _Decoration(
      size: Size(w, w * 0.5),
      painter: _SquigglePainter(color, weight),
    );
  }
}

class _Decoration extends StatelessWidget {
  const _Decoration({required this.size, required this.painter});
  final Size size;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: CustomPaint(size: size, painter: painter),
    ),
  );
}

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

/// viewBox 0 0 40 50.
class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40, size.height / 50);
    final paint = _stroke(color, 4);
    canvas
      ..drawLine(const Offset(12.5, 3), const Offset(5, 19), paint)
      ..drawLine(const Offset(31, 18), const Offset(15, 30), paint)
      ..drawLine(const Offset(17, 46), const Offset(37, 46), paint);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.color != color;
}

/// viewBox 0 0 60 30: `M5 24 C 12 10, 20 8, 28 16 S 44 26, 55 7`.
class _SquigglePainter extends CustomPainter {
  const _SquigglePainter(this.color, this.weight);
  final Color color;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 60, size.height / 30);
    final path = Path()
      ..moveTo(5, 24)
      ..cubicTo(12, 10, 20, 8, 28, 16)
      // `S`: first control point mirrors (20, 8) through (28, 16).
      ..cubicTo(36, 24, 44, 26, 55, 7);
    canvas.drawPath(path, _stroke(color, weight));
  }

  @override
  bool shouldRepaint(_SquigglePainter old) =>
      old.color != color || old.weight != weight;
}
