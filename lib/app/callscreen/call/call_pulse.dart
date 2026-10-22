import 'package:flutter/widgets.dart';

/// RN `CallPulse`: soft rings that expand from behind the avatar. Each ring
/// loops: wait `i × 1 s`, grow 1 → 1.7 over 3 s (`Easing.out(ease)`), snap
/// back. The wait sits inside the loop, so the periods are 3/4/5 s and the
/// rings drift out of their stagger, exactly as RN. Opacity peaks at .22
/// at 15 % of the growth. Ignores touches; one ticker per ring.
class CallPulse extends StatelessWidget {
  const CallPulse({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  static const ringCount = 3;
  static const grow = Duration(milliseconds: 3000);
  static const stagger = Duration(milliseconds: 1000);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < ringCount; i++)
              _Ring(index: i, size: size, color: color),
          ],
        ),
      ),
    ),
  );
}

class _Ring extends StatefulWidget {
  const _Ring({required this.index, required this.size, required this.color});

  final int index;
  final double size;
  final Color color;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    final wait = CallPulse.stagger * widget.index;
    final period = CallPulse.grow + wait;
    _c = AnimationController(vsync: this, duration: period)..repeat();
    // v: 0 while waiting, then 0 → 1 with ease-out over the growth.
    final v = _c.drive(
      CurveTween(
        curve: Interval(
          wait.inMicroseconds / period.inMicroseconds,
          1,
          curve: Curves.easeOut,
        ),
      ),
    );
    _scale = v.drive(Tween(begin: 1, end: 1.7));
    _opacity = v.drive(_PulseOpacity());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: widget.color, width: 1.5),
          ),
        ),
      ),
    ),
  );
}

/// 0 → .22 over v ∈ [0, .15], then .22 → 0 over the rest (both linear).
class _PulseOpacity extends Animatable<double> {
  static const peak = 0.22;
  static const peakAt = 0.15;

  @override
  double transform(double v) => v <= peakAt
      ? peak * v / peakAt
      : peak * (1 - (v - peakAt) / (1 - peakAt));
}
