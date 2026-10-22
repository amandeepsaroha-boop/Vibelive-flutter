import 'dart:async';

import 'package:flutter/widgets.dart';

import 'helper/call_motion.dart';

/// Moti `from → animate` once on mount (RN intro / button groups / badge).
/// Defaults are Moti's: opacity on a 300 ms timing, scale and translateY on
/// the default spring. [timing] puts everything on one timing curve instead
/// (Moti `type: 'timing'`). One controller, its own repaint layer.
class EntryIn extends StatefulWidget {
  const EntryIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.fromScale = 1,
    this.fromDy = 0,
    this.timing,
  });

  final Widget child;
  final Duration delay;
  final double fromScale;

  /// Start offset in logical px (already scaled).
  final double fromDy;
  final Duration? timing;

  @override
  State<EntryIn> createState() => _EntryInState();
}

class _EntryInState extends State<EntryIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<double> _move;
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    final timing = widget.timing;
    _c = AnimationController(
      vsync: this,
      duration: timing ?? CallMotion.springTime,
    );
    final opacityEnd = timing != null
        ? 1.0
        : CallMotion.timing.inMicroseconds /
              CallMotion.springTime.inMicroseconds;
    _opacity = _c.drive(
      CurveTween(curve: Interval(0, opacityEnd, curve: CallMotion.ease)),
    );
    _move = _c.drive(
      CurveTween(
        curve: timing != null ? CallMotion.ease : CallMotion.springCurve,
      ),
    );
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(widget.delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: FadeTransition(
      opacity: _opacity,
      child: AnimatedBuilder(
        animation: _move,
        child: widget.child,
        builder: (_, child) {
          final t = _move.value;
          final s = widget.fromScale + (1 - widget.fromScale) * t;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(0, widget.fromDy * (1 - t), 0)
              ..scaleByDouble(s, s, 1, 1),
            child: child,
          );
        },
      ),
    ),
  );
}

/// Moti `loop: true` with a timing transition: [from] → [to] and back,
/// forever (ping-pong, RN accept pulse disc / company ring).
class PingPong extends StatefulWidget {
  const PingPong({
    super.key,
    required this.child,
    required this.leg,
    this.scaleFrom = 1,
    this.scaleTo = 1,
    this.opacityFrom = 1,
    this.opacityTo = 1,
  });

  final Widget child;
  final Duration leg;
  final double scaleFrom;
  final double scaleTo;
  final double opacityFrom;
  final double opacityTo;

  @override
  State<PingPong> createState() => _PingPongState();
}

class _PingPongState extends State<PingPong>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.leg,
  )..repeat(reverse: true);
  late final Animation<double> _eased = CurvedAnimation(
    parent: _c,
    curve: CallMotion.ease,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ScaleTransition(
      scale: _eased.drive(Tween(begin: widget.scaleFrom, end: widget.scaleTo)),
      child: FadeTransition(
        opacity: _eased.drive(
          Tween(begin: widget.opacityFrom, end: widget.opacityTo),
        ),
        child: widget.child,
      ),
    ),
  );
}

/// What a [HoldBlink] animates.
enum BlinkOf { opacity, scale }

/// Moti `sequence [low, high, low]` + `loop` with [leg]-long steps (RN
/// "INCOMING CALL..." / status blink, accept-icon breathing).
class HoldBlink extends StatefulWidget {
  const HoldBlink({
    super.key,
    required this.child,
    required this.leg,
    required this.low,
    required this.high,
    this.of = BlinkOf.opacity,
  });

  final Widget child;
  final Duration leg;
  final double low;
  final double high;
  final BlinkOf of;

  @override
  State<HoldBlink> createState() => _HoldBlinkState();
}

class _HoldBlinkState extends State<HoldBlink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.leg * holdBlinkLegs,
  )..repeat();
  late final Animation<double> _value = _c.drive(
    holdBlinkSequence(widget.low, widget.high),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: switch (widget.of) {
      BlinkOf.opacity => FadeTransition(opacity: _value, child: widget.child),
      BlinkOf.scale => ScaleTransition(scale: _value, child: widget.child),
    },
  );
}
