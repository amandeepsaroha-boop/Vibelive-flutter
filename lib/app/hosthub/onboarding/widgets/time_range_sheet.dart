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

/// Start / end wheels for one day; resolves to the new slot.
Future<HostDaySlot?> showTimeRangeSheet(
  BuildContext context, {
  required String dayLabel,
  required HostDaySlot slot,
}) => showHostSheet<HostDaySlot>(
  context,
  title: 'hostflow:availability.edit_title',
  titleVariables: {'day': context.t(dayLabel)},
  child: _TimeRange(slot: slot),
);

class _TimeRange extends HookWidget {
  const _TimeRange({required this.slot});
  final HostDaySlot slot;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final starts = HostScheduleFormat.starts;
    final ends = HostScheduleFormat.ends;
    int indexOf(List<int> list, int v) {
      final i = list.indexOf(v);
      return i < 0 ? 0 : i;
    }

    final start = useState(slot.start);
    final end = useState(slot.end);
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
    final valid = end.value - start.value >= HostScheduleFormat.minSlotMinutes;

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
            child: valid
                ? null
                : Center(
                    child: CText(
                      'hostflow:errors.slot_short',
                      size: 12,
                      weight: FontWeight.w600,
                      color: p.danger,
                    ),
                  ),
          ),
          HostButton(
            label: 'hostflow:availability.save',
            arrow: false,
            onPressed: valid
                ? () => Navigator.of(context).pop(
                    slot.copyWith(
                      enabled: true,
                      start: start.value,
                      end: end.value,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
