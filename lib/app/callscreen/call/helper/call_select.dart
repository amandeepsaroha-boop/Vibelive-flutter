import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../helper/call_controller.dart';
import '../../helper/call_session.dart';
import '../../helper/engine/call_engine.dart';
import 'call_ui_state.dart';

/// Reads [select] of [listenable] and rebuilds the calling `HookWidget` only
/// when that selection changes (records compare by value, so
/// `(s.phase, s.isVideo)` is a fine selection).
S useSelect<T, S>(ValueListenable<T> listenable, S Function(T value) select) =>
    use(_SelectHook<T, S>(listenable, select));

/// [useSelect] on the session the call screen draws ([CallScope]).
S useCallSelect<S>(S Function(CallSession s) select) =>
    useSelect(CallScope.of(useContext()).session, select);

/// [useSelect] on the live media state (mute, cameras, remote uid…).
S useMediaSelect<S>(S Function(CallMedia m) select) =>
    useSelect(CallEngine.instance.media, select);

/// The call a screen is drawing, for keying its per-call state (sticky
/// session, post-call runner, guards): the live callId, kept once the call
/// resets to idle, replaced as soon as a different call is published (U5:
/// a call screen still mounted for an old call is reused by a new one).
String? useCallKey() {
  final live = useSelect(CallController.instance.session, (s) => s.callId);
  final last = useRef(live);
  if (live != null) last.value = live;
  return last.value;
}

class _SelectHook<T, S> extends Hook<S> {
  const _SelectHook(this.listenable, this.select);

  final ValueListenable<T> listenable;
  final S Function(T value) select;

  @override
  _SelectHookState<T, S> createState() => _SelectHookState<T, S>();
}

class _SelectHookState<T, S> extends HookState<S, _SelectHook<T, S>> {
  late S _last;

  @override
  void initHook() {
    super.initHook();
    hook.listenable.addListener(_onChange);
  }

  @override
  void didUpdateHook(_SelectHook<T, S> oldHook) {
    super.didUpdateHook(oldHook);
    if (oldHook.listenable != hook.listenable) {
      oldHook.listenable.removeListener(_onChange);
      hook.listenable.addListener(_onChange);
    }
  }

  // Recomputed on every build: the selector closure is new each time and
  // selecting is cheap.
  @override
  S build(BuildContext context) => _last = hook.select(hook.listenable.value);

  void _onChange() {
    if (hook.select(hook.listenable.value) != _last) setState(() {});
  }

  @override
  void dispose() => hook.listenable.removeListener(_onChange);

  @override
  String get debugLabel => 'useSelect<$S>';
}
