import 'dart:async';

import '../../helper/call_actions.dart';

/// RN `handleCallEndFeedbackTransition`, once per call (the screen keys a
/// fresh runner on every callId): the caller of a connected call gets the
/// rating sheet after [feedbackDelay]; everyone else keeps the ended summary
/// for [exitDelay], then leaves.
///
/// The step only runs while `/call` is the page on top ([isOnTop]). A page
/// pushed over the call screen (a deep link) is never yanked away or
/// covered by the sheet: the step waits until [resume] finds the call
/// screen on top again (the logic resets the call meanwhile).
class PostCallRunner {
  PostCallRunner({
    required this.onFeedback,
    required this.onExit,
    required this.isOnTop,
  });

  static const feedbackDelay = Duration(milliseconds: 300);
  static const exitDelay = Duration(milliseconds: 1200);

  final void Function() onFeedback;
  final void Function() onExit;
  final bool Function() isOnTop;

  bool _started = false;
  bool _disposed = false;
  bool _parked = false;
  bool _feedback = false;
  Timer? _timer;
  Future<void>? _hold;

  bool get started => _started;

  /// The step came due while another page was on top.
  bool get parked => _parked;

  /// Something on screen must be read first (the in-call safety "Thanks for
  /// telling us" alert): the step waits for [until] as well. RN's native
  /// alert floated over the exit; a Flutter dialog would go with the page.
  void hold(Future<void> until) => _hold = until;

  /// The call reached ended: ask the logic which step follows.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _feedback = CallActions.afterEnded() == PostCallStep.feedback;
    _timer = Timer(_feedback ? feedbackDelay : exitDelay, _due);
  }

  /// The call screen may be on top again: run a parked step now.
  /// [quietly]: the call was reset meanwhile (the logic ends a call whose
  /// screen is covered): just leave, no rating sheet.
  void resume({bool quietly = false}) {
    if (!_parked || _disposed || !isOnTop()) return;
    _parked = false;
    quietly ? onExit() : _act();
  }

  Future<void> _due() async {
    final hold = _hold;
    if (hold != null) {
      try {
        await hold;
      } catch (_) {}
    }
    _act();
  }

  void _act() {
    if (_disposed) return;
    if (!isOnTop()) {
      _parked = true;
      return;
    }
    _feedback ? onFeedback() : onExit();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
