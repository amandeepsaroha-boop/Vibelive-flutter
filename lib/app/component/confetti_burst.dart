import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A confetti burst that falls once over its box (RN `Confetti`, loop off):
/// a moment, not a state. Decorative only, so it never takes a tap.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, this.count = 55, this.seed = 7});

  final int count;

  /// Fixed scatter, so a rebuild never reshuffles the pieces.
  final int seed;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 3800);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..forward();

  late final List<_Piece> _pieces = _Piece.scatter(widget.count, widget.seed);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ConfettiPainter(_pieces, _controller),
      ),
    ),
  );
}

class _Piece {
  const _Piece({
    required this.startX,
    required this.drift,
    required this.size,
    required this.delay,
    required this.length,
    required this.color,
    required this.round,
  });

  // RN Confetti.jsx colours.
  static const _colors = [
    Color(0xFF561DE2),
    Color(0xFFFFD700),
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFF95E1D3),
    Color(0xFFF38181),
  ];

  /// 0–1 of the width.
  final double startX;

  /// Sideways travel, in fractions of the width.
  final double drift;
  final double size;

  /// Start and fall time, as fractions of the whole animation.
  final double delay;
  final double length;
  final Color color;
  final bool round;

  static List<_Piece> scatter(int count, int seed) {
    final r = math.Random(seed);
    return [
      for (var i = 0; i < count; i++)
        _Piece(
          startX: r.nextDouble(),
          drift: (r.nextDouble() - 0.5) * 0.4,
          size: r.nextDouble() * 8 + 6,
          delay: r.nextDouble() * 0.16,
          length: 0.58 + r.nextDouble() * 0.26,
          color: _colors[r.nextInt(_colors.length)],
          round: i.isEven,
        ),
    ];
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.progress) : super(repaint: progress);

  final List<_Piece> pieces;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final paint = Paint();
    for (final piece in pieces) {
      final local = ((t - piece.delay) / piece.length).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final x = (piece.startX + piece.drift * local) * size.width;
      final y = -100 + (size.height + 200) * local;
      // Fades in quickly, out over the last fifth.
      final opacity = math.min(1.0, math.min(local * 6, (1 - local) * 5));
      paint.color = piece.color.withValues(alpha: opacity);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(local * 4 * math.pi);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: piece.size,
        height: piece.size,
      );
      if (piece.round) {
        canvas.drawOval(rect, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.pieces != pieces;
}
