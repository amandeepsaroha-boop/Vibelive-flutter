import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../component/c_text.dart';
import '../helper/draft_controller.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../helper/schedule_format.dart';
import '../widgets/day_schedule_row.dart';
import '../widgets/host_switch.dart';
import '../widgets/step_body.dart';
import '../widgets/time_range_sheet.dart';

/// 8 of 11: "I'm available now" (call any time) and a weekly schedule.
class AvailabilityStep extends StatelessWidget {
  const AvailabilityStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return HostStepBody(
      title: 'hostflow:availability.title',
      subtitle: 'hostflow:availability.subtitle',
      children: [
        _ModeRow(
          switchKey: const ValueKey('hostflow-available-now'),
          icon: LucideIcons.leaf,
          iconColor: p.success,
          title: 'hostflow:availability.now',
          value: draft.availableNow,
          // RN ScheduleScreen: "anytime" and vacation exclude each other.
          onChanged: (v) {
            draft.availableNow.value = v;
            if (v) draft.vacation.value = false;
          },
        ),
        SizedBox(height: 10.ms),
        _ModeRow(
          switchKey: const ValueKey('hostflow-vacation'),
          icon: LucideIcons.plane,
          iconColor: p.accent,
          title: 'hostflow:availability.vacation',
          subtitle: 'hostflow:availability.vacation_body',
          value: draft.vacation,
          onChanged: (v) {
            draft.vacation.value = v;
            if (v) draft.availableNow.value = false;
          },
        ),
        // On vacation there is no schedule to keep (RN hides it).
        ValueListenableBuilder<bool>(
          valueListenable: draft.vacation,
          builder: (_, away, schedule) =>
              away ? const SizedBox.shrink() : schedule!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const HostLabel('hostflow:availability.weekly', top: 20),
              ValueListenableBuilder<Map<HostWeekday, HostDaySlot>>(
                valueListenable: draft.week,
                builder: (_, week, _) => Column(
                  children: [
                    for (final day in HostWeekday.values)
                      HostDayScheduleRow(
                        key: ValueKey('day-${day.name}'),
                        dayLabel: HostScheduleFormat.dayKey(day),
                        slot: week[day]!,
                        onToggle: (on) =>
                            draft.setDay(day, week[day]!.copyWith(enabled: on)),
                        onEditHours: () async {
                          final next = await showTimeRangeSheet(
                            context,
                            dayLabel: HostScheduleFormat.dayKey(day),
                            slot: week[day]!,
                          );
                          if (next != null) draft.setDay(day, next);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A toggle row ("I'm available now", "Vacation mode").
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.switchKey,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final Key switchKey;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final ValueNotifier<bool> value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return HostCard(
      padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 12.ms),
      child: Row(
        children: [
          Container(
            width: 32.ms,
            height: 32.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
            child: Icon(icon, size: 15.ms, color: AppColors.white),
          ),
          SizedBox(width: 12.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(title, size: 17, weight: FontWeight.w700, color: p.text),
                if (subtitle != null)
                  CText(
                    subtitle!,
                    size: 13,
                    weight: FontWeight.w500,
                    color: p.muted,
                  ),
              ],
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: value,
            builder: (_, on, _) => HostSwitch(
              key: switchKey,
              value: on,
              semanticLabel: context.t(title),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
