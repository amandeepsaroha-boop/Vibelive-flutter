import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Motion constants of the RN call screens (spec §0.5).
abstract final class CallMotion {
  /// Moti default timing (Reanimated `withTiming`): 300 ms, inOut(quad).
  static const timing = Duration(milliseconds: 300);
  static const ease = Curves.easeInOutQuad;

  /// Moti default spring (Reanimated 4 `withSpring`): critically damped,
  /// settled well within [springTime].
  static const spring = SpringDescription(
    mass: 4,
    stiffness: 900,
    damping: 120,
  );
  static const springTime = Duration(milliseconds: 600);
  static final springCurve = SpringCurve(spring, springTime);

  /// RN `Animated.spring({tension: 65, friction: 11})` (feedback sheet).
  static const sheetSpring = SpringDescription(
    mass: 1,
    stiffness: 320.7,
    damping: 34,
  );
  static const sheetTime = Duration(milliseconds: 500);
  static final sheetCurve = SpringCurve(sheetSpring, sheetTime);
}

/// A spring from 0 to 1 as a [Curve] over [duration] (by which time it has
/// settled), so one controller can drive spring and timing parts together.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring, this.duration)
    : _sim = SpringSimulation(spring, 0, 1, 0);

  final Duration duration;
  final SpringSimulation _sim;

  @override
  double transformInternal(double t) =>
      _sim.x(t * duration.inMicroseconds / Duration.microsecondsPerSecond);
}

/// Moti `sequence [low, high, low]` + `loop` (repeat with reverse), legs of
/// equal length: hold at [low] for one leg, then two up/down blinks, again
/// and again (spec §2.5: a 0.4↔1 blink with a hold every other cycle). Drive
/// it with a controller of `5 × leg`, repeating.
Animatable<double> holdBlinkSequence(double low, double high) {
  final up = Tween(
    begin: low,
    end: high,
  ).chain(CurveTween(curve: CallMotion.ease));
  final down = Tween(
    begin: high,
    end: low,
  ).chain(CurveTween(curve: CallMotion.ease));
  return TweenSequence([
    TweenSequenceItem(tween: ConstantTween(low), weight: 1),
    TweenSequenceItem(tween: up, weight: 1),
    TweenSequenceItem(tween: down, weight: 1),
    TweenSequenceItem(tween: up, weight: 1),
    TweenSequenceItem(tween: down, weight: 1),
  ]);
}

/// Legs in one [holdBlinkSequence] period.
const holdBlinkLegs = 5;
