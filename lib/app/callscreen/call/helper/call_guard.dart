import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// RN `DECLINE_GUARD_MS` / `HANGUP_GUARD_MS`.
const callGuardDelay = Duration(milliseconds: 2500);

/// False for [delay] after mount and again after any change of [keys], then
/// true (RN decline / hang-up guards: a tap already on its way must not end
/// a call the UI just swapped in). Shows nothing itself: RN only disabled.
///
/// [since] is when the guarded phase began (`CallSession.phaseSince`): the
/// guard then only holds for what is left of [delay], so minimizing and
/// coming back does not re-arm it (U10). Null counts from mount / the key
/// change.
bool useArmedAfter(
  Duration delay, [
  List<Object?> keys = const [],
  DateTime? since,
]) {
  // A fresh notifier per key change reads false in the very build that
  // changed the keys (no state change during build).
  final (armed, left) = useMemoized(() {
    final now = clock.now();
    var left = delay - now.difference(since ?? now);
    if (left > delay) left = delay; // clock skew: never longer than RN
    return (ValueNotifier(left <= Duration.zero), left);
  }, keys);
  useEffect(() {
    final timer = armed.value ? null : Timer(left, () => armed.value = true);
    return () {
      timer?.cancel();
      armed.dispose();
    };
  }, [armed]);
  return useValueListenable(armed);
}

/// Drops re-entrant taps while an async action runs (RN `actionInFlightRef`).
class InFlight {
  bool _busy = false;
  bool get busy => _busy;

  /// Runs [action] unless one is already running.
  Future<void> run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }
}

/// [InFlight] that lives as long as the widget.
InFlight useInFlight() => useMemoized(InFlight.new);
