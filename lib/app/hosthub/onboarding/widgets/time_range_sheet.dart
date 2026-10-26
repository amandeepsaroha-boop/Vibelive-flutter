import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../helper/schedule_format.dart';
import 'continue_bar.dart';
import 'day_schedule_row.dart';
import 'sheet_frame.dart';

/// Start / end wheels for one slot of [day] (a new one, or the one at
/// [replacing]); resolves to the slot once it passes RN's rules: end after
/// start, at least 30 minutes, no overlap with the day's other slots.
Future<HostSlot?> showTimeRangeSheet(
  BuildContext context, {
  required String dayLabel,
  required HostDaySlot day,
  required HostSlot slot,
  int? replacing,
}) => showHostSheet<HostSlot>(
  context,
  title: 'hostflow:availability.edit_title',
  titleVariables: {'day': context.t(dayLabel)},
  child: _TimeRange(day: day, slot: slot, replacing: replacing),
);

class _TimeRange extends HookWidget {
  const _TimeRange({required this.day, required this.slot, this.replacing});
  final HostDaySlot day;
  final HostSlot slot;
  final int? replacing;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final starts = HostScheduleFormat.starts;
    final ends = HostScheduleFormat.ends;
    // Saved times off the 30-minute grid open on the nearest later step.
    int indexOf(List<int> list, int v) {
      final i = list.indexWhere((m) => m >= v);
      return i < 0 ? list.length - 1 : i;
    }

    final start = useState(starts[indexOf(starts, slot.start)]);
    final end = useState(ends[indexOf(ends, slot.end)]);
    final startCtrl = useMemoized(
      () =>
          FixedExtentScrollController(initialItem: indexOf(starts, slot.start)),
    );
    final endCtrl = useMemoized(
      () => FixedExtentScrollController(initialItem: indexOf(ends, slot.end)),
    );
    useEffect(
      () => () {
        startCtrl.dispose();
        endCtrl.dispose();
      },
      const [],
    );
    final picked = HostSlot(start.value, end.value);
    final issue = day.check(picked, replacing: replacing);

    Widget wheel(
      String label,
      List<int> values,
      FixedExtentScrollController ctrl,
      ValueNotifier<int> target,
    ) => Expanded(
      child: Column(
        children: [
          CText(label, size: 13, weight: FontWeight.w600, color: p.muted),
          SizedBox(
            height: 160.ms,
            child: CupertinoPicker(
              scrollController: ctrl,
              itemExtent: 36.ms,
              onSelectedItemChanged: (i) => target.value = values[i],
              selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                background: p.tint,
              ),
              children: [
                for (final v in values)
                  Center(
                    child: CText.raw(
                      hostTimeLabel(context, v),
                      size: 16,
                      weight: FontWeight.w600,
                      color: p.text,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 4.ms),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              wheel('hostflow:availability.start', starts, startCtrl, start),
              SizedBox(width: 12.ms),
              wheel('hostflow:availability.end', ends, endCtrl, end),
            ],
          ),
          SizedBox(
            height: 28.ms,
            child: issue == null
                ? null
                : Center(
                    child: CText(
                      'hostflow:errors.$issue',
                      size: 12,
                      weight: FontWeight.w600,
                      color: p.danger,
                    ),
                  ),
          ),
          HostButton(
            label: 'hostflow:availability.save',
            arrow: false,
            onPressed: issue == null
                ? () => Navigator.of(context).pop(picked)
                : null,
          ),
        ],
      ),
    );
  }
}
