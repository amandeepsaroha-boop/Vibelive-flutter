import 'dart:math' as math;
import 'dart:ui';

/// RN `PIP_LAYOUT`: the self-view tile rests at right 18, top 132 (raw
/// points, not safe-area aware), 154×206.
abstract final class PipLayout {
  static const double right = 18;
  static const double top = 132;
  static const double width = 154;
  static const double height = 206;
  static const double radius = 18;

  /// Never touch a screen edge.
  static const double edgeMargin = 12;

  /// Stay below the header row.
  static const double headerClearance = 56;

  /// Stay above the control bar (bar + its bottom offset).
  static const double controlsClearance = 116;

  /// A press shorter than this that moved less than [tapSlop] is a tap
  /// (swap), not a drag.
  static const tapTime = Duration(milliseconds: 250);
  static const double tapSlop = 8;
}

/// RN PanResponder clamp, applied on every move: keeps the tile on screen,
/// below the header and above the controls. [offset] is from the resting
/// place; [window] the screen; [safeTop] / [safeBottom] its insets.
Offset clampPipOffset(
  Offset offset, {
  required Size window,
  required double safeTop,
  required double safeBottom,
}) {
  const w = PipLayout.width;
  const h = PipLayout.height;
  final restLeft = window.width - PipLayout.right - w;
  const restTop = PipLayout.top;

  final minX = PipLayout.edgeMargin - restLeft;
  final maxX = window.width - PipLayout.edgeMargin - w - restLeft;
  final minTop = safeTop + PipLayout.headerClearance;
  final maxBottom =
      window.height - (math.max(safeBottom, 10) + PipLayout.controlsClearance);
  final minY = minTop - restTop;
  final maxY = maxBottom - h - restTop;

  double clamp(double v, double lo, double hi) =>
      hi < lo ? lo : v.clamp(lo, hi);
  return Offset(clamp(offset.dx, minX, maxX), clamp(offset.dy, minY, maxY));
}
