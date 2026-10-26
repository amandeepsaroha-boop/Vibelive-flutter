import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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

/// 8 of 11: RN ScheduleScreen's three exclusive modes (call any time,
/// vacation, weekly slots) and, in the weekly mode, several slots per day.
///
/// The draft switches mode at once (one mode on, always); the switches
/// follow it smoothly: switching a mode off slides it off first and the
/// fallback eases on after [_stagger]; the weekly schedule fades and sizes
/// in and out.
class AvailabilityStep extends HookWidget {
  const AvailabilityStep({super.key, required this.draft});
  final HostDraftController draft;

  /// The off slide, then a short pause before the next mode slides on.
  static const _stagger = Duration(milliseconds: 220 + 150);

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    // The mode the switches show; null between "off" and the fallback.
    final shown = useMemoized(
      () => ValueNotifier<HostAvailability?>(draft.mode),
    );
    final pending = useRef<Timer?>(null);
    useEffect(() {
      final modes = Listenable.merge([draft.availableNow, draft.vacation]);
      // Prefill / restore: follow the draft unless a stagger is running.
      void sync() {
        if (pending.value?.isActive != true) shown.value = draft.mode;
      }

      modes.addListener(sync);
      return () {
        modes.removeListener(sync);
        pending.value?.cancel();
      };
    }, [draft]);
    useEffect(() => shown.dispose, const []);

    // Exactly one mode is on: switching one off falls back to the weekly
    // slots, or (for the weekly slots) to "call any time".
    void pick(HostAvailability mode, bool on) {
      pending.value?.cancel();
      final next = on
          ? mode
          : (mode == HostAvailability.custom
                ? HostAvailability.available
                : HostAvailability.custom);
      if (on) {
        // The tapped switch slides on while the old one slides off.
        shown.value = next;
        draft.mode = next;
        return;
      }
      shown.value = null;
      pending.value = Timer(_stagger, () => shown.value = next);
      draft.mode = next;
    }

    Widget mode(
      HostAvailability value, {
      required String key,
      required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
    }) => _ModeRow(
      switchKey: ValueKey(key),
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: subtitle,
      shown: shown,
      mode: value,
      onChanged: (on) => pick(value, on),
    );

    return HostStepBody(
      title: 'hostflow:availability.title',
      subtitle: 'hostflow:availability.subtitle',
      children: [
        mode(
          HostAvailability.available,
          key: 'hostflow-available-now',
          icon: LucideIcons.leaf,
          color: p.success,
          title: 'hostflow:availability.now',
          subtitle: 'hostflow:availability.now_body',
        ),
        SizedBox(height: 10.ms),
        mode(
          HostAvailability.vacation,
          key: 'hostflow-vacation',
          icon: LucideIcons.plane,
          color: p.accent,
          title: 'hostflow:availability.vacation',
          subtitle: 'hostflow:availability.vacation_body',
        ),
        SizedBox(height: 10.ms),
        mode(
          HostAvailability.custom,
          key: 'hostflow-weekly',
          icon: LucideIcons.calendarClock,
          color: p.warning,
          title: 'hostflow:availability.slots',
          subtitle: 'hostflow:availability.slots_body',
        ),
        // RN shows the custom schedule only in the weekly mode; it fades
        // out, then the space closes (and the reverse).
        RepaintBoundary(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: ValueListenableBuilder<HostAvailability?>(
              valueListenable: shown,
              builder: (_, current, schedule) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (child, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?child],
                ),
                child: current == HostAvailability.custom
                    ? schedule
                    : const SizedBox(key: ValueKey('no-schedule'), width: 1),
              ),
              child: Column(
                key: const ValueKey('weekly-schedule'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const HostLabel('hostflow:availability.weekly', top: 20),
                  ValueListenableBuilder<Map<HostWeekday, HostDaySlot>>(
                    valueListenable: draft.week,
                    builder: (_, week, _) => Column(
                      children: [
                        for (final day in HostWeekday.values)
                          _day(context, day, week[day]!),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _day(BuildContext context, HostWeekday day, HostDaySlot slots) {
    final label = HostScheduleFormat.dayKey(day);
    Future<void> edit(HostSlot slot, {int? replacing}) async {
      final next = await showTimeRangeSheet(
        context,
        dayLabel: label,
        day: slots,
        slot: slot,
        replacing: replacing,
      );
      if (next == null) return;
      final current = draft.week.value[day]!;
      // Re-checked against the day as it is now (RN `addSlot`).
      if (current.check(next, replacing: replacing) != null) return;
      draft.setDay(day, current.withSlot(next, replacing: replacing));
    }

    return HostDayScheduleRow(
      key: ValueKey('day-${day.name}'),
      dayName: day.name,
      dayLabel: label,
      day: slots,
      onToggle: (on) => draft.setDay(day, slots.toggled(on)),
      onEditSlot: (i) => edit(slots.slots[i], replacing: i),
      onRemoveSlot: (i) => draft.setDay(day, slots.withoutSlot(i)),
      onAddSlot: () => edit(slots.nextSlot),
    );
  }
}

/// A mode row ("Call any time", "Vacation mode", "Weekly slots").
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.switchKey,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.shown,
    required this.mode,
    required this.onChanged,
    this.subtitle,
  });

  final Key switchKey;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final ValueListenable<HostAvailability?> shown;
  final HostAvailability mode;
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
          ValueListenableBuilder<HostAvailability?>(
            valueListenable: shown,
            builder: (_, current, _) => HostSwitch(
              key: switchKey,
              value: current == mode,
              semanticLabel: context.t(title),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
