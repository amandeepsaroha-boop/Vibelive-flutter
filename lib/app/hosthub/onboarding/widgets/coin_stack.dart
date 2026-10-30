import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The "you earn" coins: a stack of coins, a ₹ coin in front and a little
/// sparkle. Drawn, not an image: crisp at any size and in the theme's own
/// greens (dark and light).
class CoinStack extends StatelessWidget {
  const CoinStack({
    super.key,
    required this.size,
    required this.face,
    required this.side,
    required this.ring,
    required this.glyph,
  });

  /// Width; the height is 0.82 of it.
  final double size;

  /// Coin top / front.
  final Color face;

  /// Coin edge (the stack's sides, the outlines).
  final Color side;

  /// Highlight ring and the sparkle.
  final Color ring;

  /// The ₹ on the front coin.
  final Color glyph;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size(size, size * 0.82),
      painter: _CoinPainter(face: face, side: side, ring: ring, glyph: glyph),
    ),
  );
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter({
    required this.face,
    required this.side,
    required this.ring,
    required this.glyph,
  });

  final Color face;
  final Color side;
  final Color ring;
  final Color glyph;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.022
      ..color = side;

    // The stack, bottom coin first, each a little higher.
    final cx = w * 0.62;
    final coinW = w * 0.46;
    final coinH = coinW * 0.34;
    final thick = coinH * 0.55;
    for (var i = 0; i < 4; i++) {
      final top = s.height * 0.78 - i * thick * 1.05;
      final band = Rect.fromLTWH(cx - coinW / 2, top, coinW, thick);
      final bottom = Rect.fromCenter(
        center: Offset(cx, top + thick),
        width: coinW,
        height: coinH,
      );
      final lid = Rect.fromCenter(
        center: Offset(cx, top),
        width: coinW,
        height: coinH,
      );
      final body = Path()
        ..addRect(band)
        ..addOval(bottom);
      canvas
        ..drawPath(body, Paint()..color = side)
        ..drawOval(lid, Paint()..color = face)
        ..drawOval(lid, stroke)
        ..drawOval(
          lid.deflate(coinH * 0.22),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.014
            ..color = ring.withValues(alpha: 0.8),
        );
    }

    // The ₹ coin in front.
    final c = Offset(w * 0.3, s.height * 0.66);
    final r = w * 0.2;
    canvas
      ..drawCircle(c.translate(0, r * 0.12), r, Paint()..color = side)
      ..drawCircle(c, r, Paint()..color = face)
      ..drawCircle(c, r, stroke)
      ..drawCircle(
        c,
        r * 0.78,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.018
          ..color = ring,
      );
    final rupee = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: glyph,
          fontSize: r * 1.05,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rupee.paint(
      canvas,
      c - Offset(rupee.width / 2, rupee.height / 2 + r * 0.02),
    );

    // Sparkle, top right.
    final spark = Paint()
      ..color = ring
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;
    final o = Offset(w * 0.9, s.height * 0.16);
    for (final (angle, len) in const [
      (-1.9, 0.11),
      (-1.05, 0.13),
      (-0.25, 0.1),
    ]) {
      final dir = Offset(math.cos(angle), math.sin(angle));
      final from = o + dir * (w * 0.05);
      canvas.drawLine(from, from + dir * (w * len), spark);
    }
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.face != face ||
      old.side != side ||
      old.ring != ring ||
      old.glyph != glyph;
}
