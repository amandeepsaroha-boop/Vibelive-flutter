import 'dart:math' as math;

import '../../../../core/utils/scale.dart';

/// Fixed row geometry of the call log, so the list can use exact extents.
/// Text lines use fixed line heights (`CText.height`), which keeps every
/// row's height independent of script and font.
abstract final class HistoryLayout {
  static double get gap => 10.ms;
  static double get avatar => 62.ms;
  static double get badge => 20.ms;
  static double get padV => 13.ms;
  static double get padH => 12.ms;
  static const double border = 1;
  static double get radius => 18.ms;

  /// Name / duration line.
  static const double nameLine = 20;

  /// Outcome / time line.
  static const double metaLine = 14;

  /// NUDGE pill: 4 + [metaLine] + 4.
  static double get pill => (metaLine + 8).ms;

  /// Height of the text column.
  static double content({required bool ping}) =>
      (nameLine + 3 + metaLine).ms + (ping ? 8.ms + pill : 0);

  /// Height inside the card border and padding (+1 for rounding).
  static double inner({required bool ping}) =>
      math.max(avatar, content(ping: ping) + 1);

  /// Row extent including the gap below the card.
  static double extent({required bool ping}) =>
      inner(ping: ping) + 2 * padV + 2 * border + gap;
}
