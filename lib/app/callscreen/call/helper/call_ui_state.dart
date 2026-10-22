import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../helper/call_session.dart';

/// The session a call screen draws: the live one, except that once the call
/// is reset to idle it keeps the last call (marked ended). A screen on its
/// way out never flashes "Host"/"Caller" fallbacks or an empty ring (RN kept
/// `cachedRemoteUserRef` for the same reason).
class StickySession extends ChangeNotifier
    implements ValueListenable<CallSession> {
  StickySession(this._source) : _value = _source.value {
    _source.addListener(_onSource);
  }

  final ValueListenable<CallSession> _source;
  CallSession _value;

  @override
  CallSession get value => _value;

  void _onSource() {
    final next = _source.value;
    if (next.phase == CallPhase.idle && _value.phase != CallPhase.idle) {
      // Keep what was on screen; only say it is over.
      if (_value.phase == CallPhase.ended) return;
      _value = _value.copyWith(phase: CallPhase.ended);
    } else {
      _value = next;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _source.removeListener(_onSource);
    super.dispose();
  }
}

/// Screen-local state of the call screen (RN `CallingScreen` useState):
/// each piece is its own notifier so only the widget showing it rebuilds.
class CallUiState {
  /// RN `isVideoLayoutSwapped`: own camera full screen, remote in the PiP.
  final swapped = ValueNotifier<bool>(false);

  /// "Something wrong?" panel (header flag).
  final safetyOpen = ValueNotifier<bool>(false);

  /// PiP drag offset from its resting place (RN `localPreviewPan`).
  final pipOffset = ValueNotifier<Offset>(Offset.zero);

  void dispose() {
    swapped.dispose();
    safetyOpen.dispose();
    pipOffset.dispose();
  }
}

/// Hands the drawn session (and, on the call screen, its [CallUiState]) to
/// the screen's pieces. Never rebuilds them itself: they listen.
class CallScope extends InheritedWidget {
  const CallScope({
    super.key,
    required this.session,
    this.ui,
    required super.child,
  });

  final ValueListenable<CallSession> session;
  final CallUiState? ui;

  static CallScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CallScope>();
    assert(scope != null, 'No CallScope above $context');
    return scope!;
  }

  @override
  bool updateShouldNotify(CallScope oldWidget) =>
      session != oldWidget.session || ui != oldWidget.ui;
}
