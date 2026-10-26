import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../core/theme/app_colors.dart';
import '../component/app_logo.dart';

/// "vibe meets Live": the wordmark arrives in two halves — "~vibe" from the
/// left, "Live" from the right — that meet in the middle with a little
/// bounce. Then "Live" beats twice (the app coming alive) with a soft lime
/// ripple, and keeps a gentle heartbeat while the splash waits.
///
/// One image, two clipped copies; everything repaints inside one
/// boundary. With "reduce motion" on, the logo is simply shown.
class SplashLogo extends HookWidget {
  const SplashLogo({super.key, required this.size});

  final double size;

  /// Where "~vibe" ends and "Live" starts, and the middle of "Live", as a
  /// fraction of the artwork's width (purple up to 946 px, lime from
  /// 1002 px to 1561 px of 1567 px).
  static const split = 974 / 1567;
  static const liveCenter = 1281 / 1567;

  static const intro = Duration(milliseconds: 1600);
  static const heartbeat = Duration(milliseconds: 1500);

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final enter = useAnimationController(duration: intro);
    final beat = useAnimationController(duration: heartbeat);
    useEffect(() {
      if (still) {
        enter.value = 1;
        return null;
      }
      void loop(AnimationStatus s) {
        if (s == AnimationStatus.completed) beat.repeat();
      }

      enter
        ..addStatusListener(loop)
        ..forward();
      return () => enter.removeStatusListener(loop);
    }, const []);

    final height = size * AppLogo.aspect;
    final logo = AppLogo(size: size, height: height);
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: height,
        child: AnimatedBuilder(
          animation: Listenable.merge([enter, beat]),
          child: logo,
          builder: (_, child) =>
              _frame(enter.value, beat.isAnimating ? beat.value : null, child!),
        ),
      ),
    );
  }

  static double _at(double t, double from, double to, [Curve? curve]) {
    final x = ((t - from) / (to - from)).clamp(0.0, 1.0);
    return curve?.transform(x) ?? x;
  }

  /// A beat: 0 → [amp] → 0 over [from, to].
  static double _pulse(double t, double from, double to, double amp) {
    if (t <= from || t >= to) return 0;
    return amp * math.sin(math.pi * (t - from) / (to - from));
  }

  Widget _frame(double t, double? loop, Widget logo) {
    final slide = _at(t, 0, 0.45, Curves.easeOutBack);
    final fade = _at(t, 0, 0.2, Curves.easeOut);
    final travel = size * 0.32 * (1 - slide);

    // Intro "thump-thump", then a softer one each loop.
    double scale;
    double ripple; // 0..1 progress of the lime ripple, or -1 for none
    if (loop == null) {
      scale = _pulse(t, 0.5, 0.64, 0.12) + _pulse(t, 0.68, 0.84, 0.08);
      ripple = t >= 0.5 && t < 0.95 ? (t - 0.5) / 0.45 : -1;
    } else {
      scale = _pulse(loop, 0, 0.13, 0.05) + _pulse(loop, 0.17, 0.32, 0.035);
      ripple = loop < 0.55 ? loop / 0.55 : -1;
    }
    const liveAlign = Alignment(liveCenter * 2 - 1, 0);

    return Opacity(
      opacity: fade,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (ripple >= 0)
            CustomPaint(
              painter: _Ripple(
                progress: ripple,
                strength: loop == null ? 1 : 0.6,
                center: liveCenter,
              ),
            ),
          Transform.translate(
            offset: Offset(-travel, 0),
            child: ClipRect(clipper: const _Half(left: true), child: logo),
          ),
          Transform.translate(
            offset: Offset(travel, 0),
            child: Transform.scale(
              scale: 1 + scale,
              alignment: liveAlign,
              child: ClipRect(clipper: const _Half(left: false), child: logo),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "~vibe" or the "Live" part of the artwork.
class _Half extends CustomClipper<Rect> {
  const _Half({required this.left});

  final bool left;

  @override
  Rect getClip(Size size) {
    final x = size.width * SplashLogo.split;
    return left
        ? Rect.fromLTRB(-size.width, -size.height, x, size.height * 2)
        : Rect.fromLTRB(x, -size.height, size.width * 2, size.height * 2);
  }

  @override
  bool shouldReclip(_Half old) => old.left != left;
}

/// A soft lime glow growing out of "Live" and fading.
class _Ripple extends CustomPainter {
  _Ripple({
    required this.progress,
    required this.strength,
    required this.center,
  });

  final double progress;
  final double strength;
  final double center;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOut.transform(progress);
    final c = Offset(size.width * center, size.height / 2);
    final radius = size.height * (0.4 + 1.1 * eased);
    final alpha = 0.28 * strength * (1 - progress);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            BrandColors.lime.withValues(alpha: alpha),
            BrandColors.lime.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_Ripple old) =>
      old.progress != progress || old.strength != strength;
}
