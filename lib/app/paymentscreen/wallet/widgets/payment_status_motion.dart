import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../helper/wallet_palette.dart';

/// Payment status illustrations, all custom-painted: one controller each,
/// isolated in a RepaintBoundary, so every frame is one cheap repaint of one
/// layer (no rebuilds, no saveLayer, no image assets) → smooth at 120 Hz. With
/// "reduce motion" on they jump straight to the final frame. Success is green
/// with gold coins; the confirming ring follows the wallet palette (purple in
/// light, lime in dark).

const _gold = Color(0xFFFFC94D);
const _goldDeep = Color(0xFFF2A93B);

/// The confirming ring's colours, resolved once per build.
@immutable
class _Inks {
  const _Inks({required this.accent, required this.halo});

  factory _Inks.of(BuildContext context) {
    final p = WalletPalette.of(context);
    return _Inks(
      accent: p.accent,
      halo: p.accent.withValues(alpha: p.dark ? 0.16 : 0.12),
    );
  }

  final Color accent;
  final Color halo;

  @override
  bool operator ==(Object other) =>
      other is _Inks && other.accent == accent && other.halo == halo;

  @override
  int get hashCode => Object.hash(accent, halo);
}

double _iv(double v, double a, double b, [Curve c = Curves.linear]) =>
    c.transform(((v - a) / (b - a)).clamp(0.0, 1.0));

// ── Success ────────────────────────────────────────────────────────────────
// The green disc pops in, a ring sweeps round, the check draws, a ripple
// spreads, then hearts, sparkles, gold coins and dots burst out and drift.

class PaymentSuccessBurst extends StatefulWidget {
  const PaymentSuccessBurst({super.key, this.size = 220, this.onLanded});

  final double size;

  /// Once, when the check has landed: the moment for the coin sound and to
  /// reveal the text below.
  final VoidCallback? onLanded;

  static const duration = Duration(milliseconds: 1800);

  @override
  State<PaymentSuccessBurst> createState() => _PaymentSuccessBurstState();
}

class _PaymentSuccessBurstState extends State<PaymentSuccessBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PaymentSuccessBurst.duration,
  );
  final List<_Particle> _particles = _Particle.burst(seed: 7, count: 24);
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  void _onTick() {
    if (_landed || _c.value < 0.34) return;
    _landed = true;
    widget.onLanded?.call();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size.ms,
        child: CustomPaint(
          painter: _SuccessPainter(
            _c,
            _particles,
            dark: WalletPalette.of(context).dark,
          ),
        ),
      ),
    );
  }
}

class _SuccessPainter extends CustomPainter {
  _SuccessPainter(this.t, this.particles, {required this.dark})
    : super(repaint: t);

  final Animation<double> t;
  final List<_Particle> particles;
  final bool dark;

  static const _green = StatusColors.success;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final c = size.center(Offset.zero);
    final r = size.width * 0.27;

    // Ripple, then the soft halo fading in.
    final ripple = _iv(v, 0.2, 0.8, Curves.easeOutCubic);
    if (ripple > 0 && ripple < 1) {
      canvas.drawCircle(
        c,
        r * (1 + 0.85 * ripple),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.012
          ..color = _green.withValues(alpha: 0.35 * (1 - ripple)),
      );
    }
    final halo = _iv(v, 0.0, 0.4, Curves.easeOut);
    final soft = dark
        ? _green.withValues(alpha: 0.22)
        : StatusColors.successSoft;
    canvas.drawCircle(
      c,
      r * 1.32 * halo,
      Paint()..color = soft.withValues(alpha: soft.a * halo),
    );

    // Disc pops in with a little overshoot.
    final pop = _iv(v, 0.04, 0.36, Curves.easeOutBack);
    if (pop > 0) canvas.drawCircle(c, r * pop, Paint()..color = _green);

    // Ring sweeps around the disc.
    final sweep = _iv(v, 0.08, 0.42, Curves.easeInOutCubic);
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r * 1.14),
        -math.pi / 2,
        2 * math.pi * sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = size.width * 0.018
          ..color = _green.withValues(alpha: 0.55),
      );
    }

    // Checkmark strokes in.
    final check = _iv(v, 0.3, 0.56, Curves.easeOutCubic);
    if (check > 0) {
      final path = Path()
        ..moveTo(c.dx - r * 0.42, c.dy + r * 0.02)
        ..lineTo(c.dx - r * 0.1, c.dy + r * 0.34)
        ..lineTo(c.dx + r * 0.46, c.dy - r * 0.3);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * check),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = size.width * 0.05
          ..color = AppColors.white,
      );
    }

    // Particle burst.
    final burst = _iv(v, 0.32, 1.0);
    if (burst > 0 && burst < 1) {
      for (final p in particles) {
        p.paint(canvas, c, r, burst, size.width);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessPainter old) => old.dark != dark;
}

enum _Shape { heart, sparkle, coin, dot }

class _Particle {
  _Particle(
    this.angle,
    this.distance,
    this.size,
    this.shape,
    this.color,
    this.delay,
    this.spin,
  );

  final double angle;
  final double distance; // in disc radii
  final double size; // fraction of canvas width
  final _Shape shape;
  final Color color;
  final double delay; // 0..0.25 of the burst window
  final double spin;

  // Brand purple and lavender, a soft pink, brand lime (coins are gold).
  static const _colors = [
    BrandColors.purple,
    BrandColors.purpleLight,
    Color(0xFFFF8FAB),
    BrandColors.lime,
  ];

  static List<_Particle> burst({required int seed, required int count}) {
    final rnd = math.Random(seed);
    return [
      for (var i = 0; i < count; i++)
        _Particle(
          (i / count) * 2 * math.pi + rnd.nextDouble() * 0.35,
          1.45 + rnd.nextDouble() * 0.85,
          0.028 + rnd.nextDouble() * 0.03,
          _Shape.values[i % _Shape.values.length],
          _colors[rnd.nextInt(_colors.length)],
          rnd.nextDouble() * 0.25,
          (rnd.nextDouble() - 0.5) * 2.4,
        ),
    ];
  }

  void paint(Canvas canvas, Offset c, double r, double burst, double w) {
    final local = ((burst - delay) / (1 - delay)).clamp(0.0, 1.0);
    if (local <= 0) return;
    final travel = Curves.easeOutCubic.transform(local);
    final d = r * (0.9 + (distance - 0.9) * travel);
    final pos =
        c +
        Offset(
          math.cos(angle) * d,
          math.sin(angle) * d + w * 0.05 * local * local,
        );
    final opacity = (1 - math.pow(local, 1.6)).clamp(0.0, 1.0).toDouble();
    final s =
        w *
        size *
        (0.6 + 0.4 * Curves.easeOutBack.transform(math.min(1, local * 2.5)));
    final paint = Paint()..color = color.withValues(alpha: opacity);

    canvas
      ..save()
      ..translate(pos.dx, pos.dy)
      ..rotate(spin * local);
    switch (shape) {
      case _Shape.dot:
        canvas.drawCircle(Offset.zero, s * 0.38, paint);
      case _Shape.coin:
        canvas
          ..drawCircle(
            Offset.zero,
            s * 0.62,
            Paint()..color = _goldDeep.withValues(alpha: opacity),
          )
          ..drawCircle(
            Offset.zero,
            s * 0.44,
            Paint()..color = _gold.withValues(alpha: opacity),
          );
      case _Shape.sparkle:
        final p = Path()
          ..moveTo(0, -s)
          ..quadraticBezierTo(0, 0, s, 0)
          ..quadraticBezierTo(0, 0, 0, s)
          ..quadraticBezierTo(0, 0, -s, 0)
          ..quadraticBezierTo(0, 0, 0, -s)
          ..close();
        canvas.drawPath(p, paint);
      case _Shape.heart:
        final h = s * 1.1;
        final p = Path()
          ..moveTo(0, h * 0.35)
          ..cubicTo(-h * 0.9, -h * 0.25, -h * 0.35, -h * 0.85, 0, -h * 0.35)
          ..cubicTo(h * 0.35, -h * 0.85, h * 0.9, -h * 0.25, 0, h * 0.35)
          ..close();
        canvas.drawPath(p, paint);
    }
    canvas.restore();
  }
}

// ── Failed / cancelled ─────────────────────────────────────────────────────
// A soft disc pops in, the mark draws, one gentle wobble.

enum PaymentMarkKind { failed, cancelled }

class PaymentStatusMark extends StatefulWidget {
  const PaymentStatusMark({super.key, required this.kind, this.size = 170});

  final PaymentMarkKind kind;
  final double size;

  @override
  State<PaymentStatusMark> createState() => _PaymentStatusMarkState();
}

class _PaymentStatusMarkState extends State<PaymentStatusMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size.ms,
        child: CustomPaint(painter: _MarkPainter(_c, widget.kind)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t, this.kind) : super(repaint: t);

  final Animation<double> t;
  final PaymentMarkKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final failed = kind == PaymentMarkKind.failed;
    final accent = failed ? StatusColors.danger : StatusColors.warning;
    final r = size.width * 0.33;
    // One soft, decaying wobble after the mark lands (never harsh).
    final wobbleT = _iv(v, 0.62, 1.0);
    final wobble =
        math.sin(wobbleT * math.pi * 3) * (1 - wobbleT) * size.width * 0.025;
    final c = size.center(Offset.zero) + Offset(wobble, 0);

    final halo = _iv(v, 0.0, 0.45, Curves.easeOut);
    canvas.drawCircle(
      c,
      r * 1.3 * halo,
      Paint()..color = accent.withValues(alpha: 0.14 * halo),
    );
    final pop = _iv(v, 0.05, 0.4, Curves.easeOutBack);
    if (pop > 0) {
      canvas.drawCircle(
        c,
        r * pop,
        Paint()..color = accent.withValues(alpha: 0.22),
      );
    }

    final draw = _iv(v, 0.3, 0.62, Curves.easeOutCubic);
    if (draw <= 0) return;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.055
      ..color = accent;
    final k = r * 0.38;
    final Path path;
    if (failed) {
      path = Path()
        ..moveTo(c.dx - k, c.dy - k)
        ..lineTo(c.dx + k, c.dy + k)
        ..moveTo(c.dx + k, c.dy - k)
        ..lineTo(c.dx - k, c.dy + k);
    } else {
      // Pause bars: "paused, not lost".
      path = Path()
        ..moveTo(c.dx - k * 0.45, c.dy - k)
        ..lineTo(c.dx - k * 0.45, c.dy + k)
        ..moveTo(c.dx + k * 0.45, c.dy - k)
        ..lineTo(c.dx + k * 0.45, c.dy + k);
    }
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * draw), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.kind != kind;
}

// ── Confirming ─────────────────────────────────────────────────────────────
// A calm arc turns around a breathing gold coin.

class PaymentConfirmingRing extends StatefulWidget {
  const PaymentConfirmingRing({super.key, this.size = 170});
  final double size;

  @override
  State<PaymentConfirmingRing> createState() => _PaymentConfirmingRingState();
}

class _PaymentConfirmingRingState extends State<PaymentConfirmingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0.25;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size.ms,
        child: CustomPaint(painter: _ConfirmingPainter(_c, _Inks.of(context))),
      ),
    );
  }
}

class _ConfirmingPainter extends CustomPainter {
  _ConfirmingPainter(this.t, this.inks) : super(repaint: t);

  final Animation<double> t;
  final _Inks inks;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final c = size.center(Offset.zero);
    final r = size.width * 0.36;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..color = inks.halo,
    );
    final breathe = 0.5 + 0.5 * math.sin(v * 2 * math.pi);
    canvas
      ..drawCircle(
        c,
        r * (0.44 + 0.06 * breathe),
        Paint()..color = _gold.withValues(alpha: 0.25),
      )
      ..drawCircle(c, r * 0.3, Paint()..color = _goldDeep)
      ..drawCircle(c, r * 0.22, Paint()..color = _gold);
    final start = v * 2 * math.pi - math.pi / 2;
    final sweep = math.pi * (0.45 + 0.35 * breathe);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.width * 0.03
        ..color = inks.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _ConfirmingPainter old) => old.inks != inks;
}
