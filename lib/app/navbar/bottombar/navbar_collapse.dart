import 'package:flutter/widgets.dart';

/// Shrinks the bottom navbar while a feed scrolls down, restores it when
/// scrolling up or at the top (RN `scroll.js`). Only the navbar listens, so
/// scrolling rebuilds nothing else.
class NavbarCollapse extends ValueNotifier<bool> {
  NavbarCollapse._() : super(false);
  static final NavbarCollapse instance = NavbarCollapse._();

  /// Finger travel against the current direction before the bar flips:
  /// small reversals (momentum ending, a page appended) must not jitter it.
  static const _flipDistance = 28.0;

  /// Null after [reset]: a kept-alive feed may be anywhere (tabs keep their
  /// offset), so its first sample only sets the baseline.
  double? _lastY = 0;
  double _travel = 0;
  bool _down = false;

  /// Feed one scroll position (from `InfiniteScroll.onScroll`).
  void track(ScrollMetrics m) {
    final y = m.pixels;
    if (y <= 0) {
      _lastY = 0;
      _travel = 0;
      _down = false;
      value = false;
      return;
    }
    // Bounce past the end is not a reversal.
    if (y >= m.maxScrollExtent) {
      _lastY = m.maxScrollExtent;
      _travel = 0;
      return;
    }
    final last = _lastY;
    if (last == null) {
      _lastY = y;
      return;
    }
    final diff = y - last;
    _lastY = y;
    final down = diff > 0;
    if (down != _down) {
      _travel += diff.abs();
      if (_travel < _flipDistance) return;
      _down = down;
    }
    _travel = 0;
    value = _down;
  }

  /// Open without animation (screen shown, tab switched).
  void reset() {
    _lastY = null;
    _travel = 0;
    _down = false;
    value = false;
  }
}
