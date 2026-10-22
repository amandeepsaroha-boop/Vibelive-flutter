import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../core/i18n/i18n.dart';
import '../../core/utils/scale.dart';
import '../api/splashscreen/splash_queries.dart';
import '../component/c_image.dart';
import '../component/c_text.dart';
import 'splash_palette.dart';

// Performance: one Ticker per visual (display rate, 120 Hz on ProMotion and
// high-refresh Android). Painters and transforms read that clock inside
// their own RepaintBoundary, so each frame repaints only what moves and
// rebuilds nothing.

/// Seconds since mount, updated every frame.
ValueListenable<double> _useClock() {
  final clock = useValueNotifier(0.0);
  final vsync = useSingleTickerProvider();
  useEffect(() {
    final ticker = vsync.createTicker(
      (elapsed) => clock.value = elapsed.inMicroseconds / 1e6,
    )..start();
    return ticker.dispose;
  }, const []);
  return clock;
}

/// 0 → 1 → 0 over [period] seconds, [curve] on both halves.
double _pingPong(double t, double period, [Curve curve = Curves.easeInOut]) {
  final p = t % period / period * 2;
  return curve.transform(p < 1 ? p : 2 - p);
}

/// Re-transforms a cached [child] each tick.
class _Moving extends StatelessWidget {
  const _Moving({
    required this.clock,
    required this.matrix,
    required this.child,
  });

  final ValueListenable<double> clock;
  final Matrix4 Function(double t) matrix;
  final Widget child;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: clock,
      child: RepaintBoundary(child: child),
      builder: (_, c) => Transform(
        transform: matrix(clock.value),
        alignment: Alignment.center,
        child: c,
      ),
    ),
  );
}

/// Expanding/fading circle around the centre of its [Stack] (may overflow).
class _Pulse extends StatelessWidget {
  const _Pulse(
    this.clock, {
    required this.radius,
    required this.color,
    required this.frame,
  });

  final ValueListenable<double> clock;
  final double radius;
  final Color color;

  /// (scale, opacity) at time t.
  final (double, double) Function(double t) frame;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: RepaintBoundary(child: CustomPaint(painter: _PulsePainter(this))),
  );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.pulse) : super(repaint: pulse.clock);
  final _Pulse pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final (scale, opacity) = pulse.frame(pulse.clock.value);
    canvas.drawCircle(
      size.center(Offset.zero),
      pulse.radius * scale,
      Paint()..color = pulse.color.withValues(alpha: pulse.color.a * opacity),
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.pulse.radius != pulse.radius;
}

// ── Slide 1: what hosts help with, two columns drifting opposite ways ──

class InterestVisual extends HookWidget {
  const InterestVisual({super.key});

  static const _fallbackCount = 10;

  @override
  Widget build(BuildContext context) {
    final fetched = useHostTopics(context).data;
    final topics = (fetched == null || fetched.isEmpty)
        ? [
            for (var i = 0; i < _fallbackCount; i++)
              context.t('splash:topics.t$i'),
          ]
        : fetched;
    final half = math.max(3, (topics.length / 2).ceil());
    final a = topics.take(half).toList();
    final rest = topics.skip(half).toList();
    final clock = _useClock();
    final palette = SplashPalette.of(context);

    Widget fade(bool top) => Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: 60.ms,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [palette.bg, palette.bgClear],
          ),
        ),
      ),
    );

    return SizedBox(
      height: 260.ms,
      child: ClipRect(
        child: Stack(
          children: [
            Row(
              children: [
                const Spacer(flex: 6),
                // RN: 360 px in 12 s up, 360 px in 16 s down.
                Expanded(
                  flex: 44,
                  child: _Marquee(a, clock, speed: 30.ms, up: true),
                ),
                Expanded(
                  flex: 44,
                  child: _Marquee(
                    rest.length >= 3 ? rest : a,
                    clock,
                    speed: 22.5.ms,
                    up: false,
                  ),
                ),
                const Spacer(flex: 6),
              ],
            ),
            fade(true),
            fade(false),
          ],
        ),
      ),
    );
  }
}

/// Endless column of chips. It moves exactly one cycle per loop, so the
/// wrap is invisible (RN moved a fixed 360 px and visibly jumped).
class _Marquee extends StatelessWidget {
  const _Marquee(
    this.labels,
    this.clock, {
    required this.speed,
    required this.up,
  });

  final List<String> labels;
  final ValueListenable<double> clock;
  final double speed;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final cycle = labels.length * 60.ms; // chip 42 + gap 18
    final copies = (260.ms / cycle).ceil() + 1;
    return OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: double.infinity,
      child: _Moving(
        clock: clock,
        matrix: (t) {
          final o = t * speed % cycle;
          return Matrix4.translationValues(0, up ? -o : o - cycle, 0);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var c = 0; c < copies; c++)
              for (final label in labels) _Chip(label),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = SplashPalette.of(context);
    return Container(
      height: 42.ms,
      margin: EdgeInsets.only(bottom: 18.ms),
      padding: EdgeInsets.symmetric(horizontal: 18.ms),
      decoration: BoxDecoration(
        color: palette.chipBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.chipBorder),
      ),
      child: Align(
        widthFactor: 1,
        child: CText.raw(
          label,
          size: 13,
          height: 18,
          weight: FontWeight.w700,
          color: palette.chipText,
          maxLines: 2,
          align: TextAlign.center,
        ),
      ),
    );
  }
}

// ── Slide 2: pay per minute ────────────────────────────────────────────

class PayVisual extends HookWidget {
  const PayVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final clock = _useClock();
    final palette = SplashPalette.of(context);
    return SizedBox(
      width: double.infinity,
      height: 260.ms,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          _Pulse(
            clock,
            radius: 80.ms,
            color: palette.ping,
            frame: (t) {
              final v = Curves.easeOutCubic.transform(t % 1.7 / 1.7);
              return (1 + 0.75 * v, 0.3 * (1 - v));
            },
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 36.ms, vertical: 30.ms),
            decoration: BoxDecoration(
              color: palette.cardBg,
              borderRadius: BorderRadius.circular(52.ms),
              border: Border.all(color: palette.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size(70.ms, 56.ms),
                    painter: _WavePainter(clock, palette.accent),
                  ),
                ),
                SizedBox(height: 16.ms),
                CText(
                  'splash:pay.per_minute',
                  italic: true,
                  color: palette.accent,
                  size: 26,
                  weight: FontWeight.w900,
                  letterSpacing: 1.5,
                  uppercase: true,
                ),
                SizedBox(height: 8.ms),
                CText(
                  'splash:pay.only_when_talking',
                  variant: CTextVariant.caption,
                  color: palette.muted,
                  letterSpacing: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven bars bouncing in a staggered wave (RN: 540 ms up, 540 ms down,
/// each bar delayed 90 ms more than the previous, every cycle).
class _WavePainter extends CustomPainter {
  _WavePainter(this.clock, this.color) : super(repaint: clock);
  final ValueListenable<double> clock;
  final Color color;

  static const _heights = [8, 16, 24, 14, 30, 18, 10];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final width = 6.ms, step = size.width / _heights.length;
    for (var i = 0; i < _heights.length; i++) {
      final h = _heights[i].ms, delay = 0.09 * i;
      final p = clock.value % (1.08 + delay);
      final v = p < delay ? 0.0 : _pingPong(p - delay, 1.08);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              step * (i + 0.5),
              size.height - h / 2 + h * (0.05 - 0.2 * v),
            ),
            width: width,
            height: h * (0.9 + 0.4 * v),
          ),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.color != color;
}

// ── Slide 3: two floating cards, voice or video ────────────────────────

class LiveVisual extends HookWidget {
  const LiveVisual({super.key});

  static const _avatar =
      'https://api.dicebear.com/7.x/avataaars/png?size=180&seed=';

  @override
  Widget build(BuildContext context) {
    final clock = _useClock();
    final palette = SplashPalette.of(context);
    Widget card(String seed, double degrees, double delay, double period) =>
        _Moving(
          clock: clock,
          matrix: (t) {
            final p = t % period;
            final v = p < delay
                ? 0.0
                : _pingPong(p - delay, 4, Curves.easeInOutSine);
            return Matrix4.rotationZ(degrees * math.pi / 180)
              ..translateByDouble(0, -15.ms * v, 0, 1);
          },
          child: Container(
            width: 98.ms,
            height: 136.ms,
            padding: EdgeInsets.all(4.ms),
            decoration: BoxDecoration(
              color: palette.shellBg,
              borderRadius: BorderRadius.circular(34.ms),
              border: Border.all(color: palette.shellBorder, width: 1.ms),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30.ms),
              child: ColoredBox(
                color: palette.inner,
                child: CImage(
                  url: '$_avatar$seed',
                  width: 88.ms,
                  height: 126.ms,
                  placeholder: const SizedBox.shrink(),
                  errorWidget: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );

    return SizedBox(
      width: double.infinity,
      height: 240.ms,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          _Pulse(
            clock,
            radius: 160.ms,
            color: palette.liveGlow,
            frame: (t) {
              final v = _pingPong(t, 3.6);
              return (1 + 0.2 * v, 0.2 - 0.14 * v);
            },
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              card('vibeA', -6, 0, 4),
              _SyncDot(palette),
              card('vibeB', 6, 1, 5),
            ],
          ),
          Positioned(
            bottom: 8.ms,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.ms, vertical: 7.ms),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: CText(
                'splash:choose.badge',
                variant: CTextVariant.caption,
                color: palette.onAccent,
                weight: FontWeight.w900,
                letterSpacing: 2.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot(this.palette);
  final SplashPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 34.ms,
    height: 34.ms,
    margin: EdgeInsets.symmetric(horizontal: 14.ms),
    decoration: BoxDecoration(
      color: palette.accent,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: palette.accent.withValues(alpha: 0.7),
          blurRadius: 12.ms,
        ),
      ],
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        for (final angle in const [math.pi / 4, -math.pi / 4])
          Transform.rotate(
            angle: angle,
            child: SizedBox(
              width: 16.ms,
              height: 2.ms,
              child: ColoredBox(color: palette.onAccent),
            ),
          ),
      ],
    ),
  );
}
