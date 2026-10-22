import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../helper/schedule_format.dart';
import 'host_switch.dart';

/// "6:00 PM" in the current language.
String hostTimeLabel(BuildContext context, int minutes) {
  final t = HostScheduleFormat.parts(minutes);
  return context.t(
    'hostflow:availability.time',
    variables: {
      'h': t.h,
      'm': t.m,
      'period': context.t(
        t.pm ? 'hostflow:availability.pm' : 'hostflow:availability.am',
      ),
    },
  );
}

/// One weekday: name, its hours (tap to edit) or "Unavailable", a switch.
class HostDayScheduleRow extends StatelessWidget {
  const HostDayScheduleRow({
    super.key,
    required this.dayLabel,
    required this.slot,
    required this.onToggle,
    required this.onEditHours,
  });

  /// i18n key ("Mon").
  final String dayLabel;
  final HostDaySlot slot;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEditHours;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final on = slot.enabled;
    return Container(
      height: 46.ms,
      margin: EdgeInsets.only(bottom: 6.ms),
      padding: EdgeInsets.only(left: 14.ms, right: 10.ms),
      decoration: BoxDecoration(
        color: p.neutral,
        borderRadius: BorderRadius.circular(12.ms),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56.ms,
            child: CText(
              dayLabel,
              size: 15.5,
              weight: FontWeight.w600,
              color: on ? p.text : p.muted,
              maxLines: 1,
            ),
          ),
          Expanded(
            child: on
                ? Pressable(
                    onPressed: onEditHours,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: CText(
                        'hostflow:availability.range',
                        variables: {
                          'start': hostTimeLabel(context, slot.start),
                          'end': hostTimeLabel(context, slot.end),
                        },
                        size: 15.5,
                        weight: FontWeight.w500,
                        color: p.text,
                        maxLines: 1,
                      ),
                    ),
                  )
                : CText(
                    'hostflow:availability.unavailable',
                    size: 15.5,
                    weight: FontWeight.w500,
                    color: p.faint,
                    maxLines: 1,
                  ),
          ),
          SizedBox(width: 8.ms),
          HostSwitch(
            value: on,
            onChanged: onToggle,
            semanticLabel: context.t(dayLabel),
            width: 46,
            height: 28,
          ),
        ],
      ),
    );
  }
}
