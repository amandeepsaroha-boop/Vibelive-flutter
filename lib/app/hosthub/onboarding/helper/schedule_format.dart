import '../../../api/hosthub/profile_models.dart';
import 'draft_models.dart';

/// Times of the weekly schedule: 30-minute steps, labelled "6:00 PM".
abstract final class HostScheduleFormat {
  static const stepMinutes = 30;
  static const minSlotMinutes = HostDaySlot.minSlotMinutes;

  /// Start choices: 12:00 AM … 11:30 PM.
  static final List<int> starts = [
    for (var m = 0; m < 24 * 60; m += stepMinutes) m,
  ];

  /// End choices: 12:30 AM … 11:30 PM, then "12:00 AM" (end of day).
  static final List<int> ends = [
    for (var m = stepMinutes; m < 24 * 60; m += stepMinutes) m,
    HostDaySlot.endOfDay,
  ];

  /// `{h, m, period}` for the `hostflow:availability.time` template; the end
  /// of day reads as 12:00 AM.
  static ({int h, String m, bool pm}) parts(int minutes) {
    final total = minutes == HostDaySlot.endOfDay ? 0 : minutes % (24 * 60);
    final h24 = total ~/ 60;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return (h: h12, m: (total % 60).toString().padLeft(2, '0'), pm: h24 >= 12);
  }

  /// Short day keys, Monday first.
  static String dayKey(HostWeekday d) => 'hostflow:availability.days.${d.name}';
}
