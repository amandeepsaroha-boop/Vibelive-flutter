import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'c_toast.dart';

/// Android back on an entry screen (splash, login, onboarding, Home): the
/// first press shows "Press back again to exit", a second one within 2 s
/// leaves the app (RN `useAndroidBackHandler`). iOS has no back key, and the
/// first route has no swipe-back, so nothing changes there.
///
/// [onBack] runs first and returns true when it used the press (Home's other
/// tabs go back to Discover, login's code step back to the email step).
/// A screen pushed over another route pops normally.
class ExitOnDoubleBack extends StatefulWidget {
  const ExitOnDoubleBack({super.key, required this.child, this.onBack});

  final Widget child;
  final bool Function()? onBack;

  static const window = Duration(seconds: 2);

  @override
  State<ExitOnDoubleBack> createState() => _ExitOnDoubleBackState();
}

class _ExitOnDoubleBackState extends State<ExitOnDoubleBack> {
  DateTime? _firstPress;
  bool _root = true;

  void _onPop(bool didPop, Object? result) {
    if (didPop || (widget.onBack?.call() ?? false)) return;
    if (!_root) return Navigator.of(context).pop(result);
    final now = clock.now();
    final first = _firstPress;
    if (first != null && now.difference(first) < ExitOnDoubleBack.window) {
      _firstPress = null;
      SystemNavigator.pop();
      return;
    }
    _firstPress = now;
    CToast.show('back_to_exit', duration: ExitOnDoubleBack.window);
  }

  @override
  Widget build(BuildContext context) {
    // Something underneath (e.g. login pushed over Home): a normal back,
    // unless [onBack] wants the press.
    _root = ModalRoute.of(context)?.isFirst ?? true;
    return PopScope(
      canPop: !_root && widget.onBack == null,
      onPopInvokedWithResult: _onPop,
      child: widget.child,
    );
  }
}
