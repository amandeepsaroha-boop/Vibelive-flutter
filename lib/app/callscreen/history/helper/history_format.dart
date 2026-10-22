import 'package:intl/intl.dart';

/// Call-log time, date and duration text (RN explore `formatTime`,
/// `formatTs`, `durationLabel`), in the app language.
class HistoryFormat {
  HistoryFormat._(this._time, this._date);

  /// Formatters are built once per language. A locale whose date symbols are
  /// not loaded (tests, an unexpected tag) falls back to RN's `en-US`.
  factory HistoryFormat.of(String localeTag) =>
      _cache[localeTag] ??= _build(localeTag);

  static final _cache = <String, HistoryFormat>{};

  static HistoryFormat _build(String tag) {
    try {
      return HistoryFormat._(DateFormat.jm(tag), DateFormat.yMMMd(tag));
    } catch (_) {
      return HistoryFormat._(DateFormat.jm('en_US'), DateFormat.yMMMd('en_US'));
    }
  }

  final DateFormat _time;
  final DateFormat _date;

  /// `3:05 PM • OCT 21, 2026`.
  String when(DateTime at) =>
      '${_time.format(at)} • ${_date.format(at).toUpperCase()}';

  /// Talk time as `m:ss`; null without seconds (RN then fell back to the
  /// `duration` minutes, see [minutes]).
  static String? clock(int seconds) => seconds > 0
      ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
      : null;

  /// Minutes without trailing `.0`; null when there are none.
  static String? minutes(num minutes) {
    if (minutes <= 0) return null;
    return minutes == minutes.roundToDouble()
        ? minutes.toInt().toString()
        : minutes.toString();
  }
}
