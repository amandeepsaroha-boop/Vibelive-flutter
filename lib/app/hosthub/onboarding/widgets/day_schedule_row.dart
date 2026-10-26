import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

/// "6:00 PM – 12:00 AM".
String hostRangeLabel(BuildContext context, HostSlot slot) => context.t(
  'hostflow:availability.range',
  variables: {
    'start': hostTimeLabel(context, slot.start),
    'end': hostTimeLabel(context, slot.end),
  },
);

/// One weekday (RN ScheduleScreen): name and a switch; when on, its slots
/// (tap to edit, x to remove) and "Add slot".
class HostDayScheduleRow extends StatelessWidget {
  const HostDayScheduleRow({
    super.key,
    required this.dayName,
    required this.dayLabel,
    required this.day,
    required this.onToggle,
    required this.onEditSlot,
    required this.onRemoveSlot,
    required this.onAddSlot,
  });

  /// `HostWeekday.name`, for the test keys.
  final String dayName;

  /// i18n key ("Mon").
  final String dayLabel;
  final HostDaySlot day;
  final ValueChanged<bool> onToggle;
  final ValueChanged<int> onEditSlot;
  final ValueChanged<int> onRemoveSlot;
  final VoidCallback onAddSlot;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final on = day.enabled;
    return Container(
      margin: EdgeInsets.only(bottom: 6.ms),
      padding: EdgeInsets.fromLTRB(14.ms, 0, 10.ms, on ? 10.ms : 0),
      decoration: BoxDecoration(
        color: p.neutral,
        borderRadius: BorderRadius.circular(12.ms),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 46.ms,
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
                      ? const SizedBox.shrink()
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
          ),
          if (on) ...[
            for (var i = 0; i < day.slots.length; i++)
              _SlotRow(
                key: ValueKey('slot-$dayName-$i'),
                label: hostRangeLabel(context, day.slots[i]),
                removeKey: ValueKey('slot-remove-$dayName-$i'),
                onEdit: () => onEditSlot(i),
                onRemove: () => onRemoveSlot(i),
              ),
            Pressable(
              key: ValueKey('slot-add-$dayName'),
              onPressed: onAddSlot,
              child: Container(
                height: 36.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: p.cardBorder),
                  borderRadius: BorderRadius.circular(10.ms),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.plus, size: 15.ms, color: p.accent),
                    SizedBox(width: 6.ms),
                    CText(
                      'hostflow:availability.add_slot',
                      size: 14,
                      weight: FontWeight.w600,
                      color: p.accent,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One slot: its range (tap to edit) and a remove button.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    super.key,
    required this.label,
    required this.removeKey,
    required this.onEdit,
    required this.onRemove,
  });

  final String label;
  final Key removeKey;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      height: 40.ms,
      margin: EdgeInsets.only(bottom: 6.ms),
      padding: EdgeInsets.only(left: 12.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10.ms),
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onPressed: onEdit,
              child: Align(
                alignment: Alignment.centerLeft,
                child: CText.raw(
                  label,
                  size: 15,
                  weight: FontWeight.w500,
                  color: p.text,
                  maxLines: 1,
                ),
              ),
            ),
          ),
          Pressable(
            key: removeKey,
            onPressed: onRemove,
            semanticLabel: context.t('hostflow:availability.remove_slot'),
            child: SizedBox(
              width: 40.ms,
              height: 40.ms,
              child: Icon(LucideIcons.x, size: 16.ms, color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}
