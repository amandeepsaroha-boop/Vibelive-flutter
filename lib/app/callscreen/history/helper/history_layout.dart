import 'dart:math' as math;

import '../../../../core/utils/scale.dart';

/// Fixed row geometry of the call log, so the list can use exact extents.
/// One continuous list: rows flush to the edges, a single 1 px line under
/// each (no gaps, no rounded cards); only the content is inset.
/// Text lines use fixed line heights (`CText.height`), which keeps every
/// row's height independent of script and font.
abstract final class HistoryLayout {
  static const double gap = 0;
  static double get avatar => 62.ms;
  static double get badge => 20.ms;
  static double get padV => 13.ms;
  static double get padH => 16.ms;

  /// The divider under each row.
  static const double border = 1;

  /// Name / duration line.
  static const double nameLine = 20;

  /// Outcome / time line.
  static const double metaLine = 14;

  /// NUDGE pill: 4 + [metaLine] + 4.
  static double get pill => (metaLine + 8).ms;

  /// Height of the text column.
  static double content({required bool ping}) =>
      (nameLine + 3 + metaLine).ms + (ping ? 8.ms + pill : 0);

  /// Height inside the padding and divider (+1 for rounding).
  static double inner({required bool ping}) =>
      math.max(avatar, content(ping: ping) + 1);

  /// Row extent: content, padding and the divider below it.
  static double extent({required bool ping}) =>
      inner(ping: ping) + 2 * padV + border + gap;
}
