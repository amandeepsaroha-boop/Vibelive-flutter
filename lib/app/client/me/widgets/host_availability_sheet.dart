import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../hosthub/onboarding/helper/host_funnel.dart';
import '../helper/host_availability_controller.dart';
import '../helper/me_actions.dart';
import '../helper/me_data.dart';

/// Status colours of the three modes (light tints work on dark too).
abstract final class HostStatusColors {
  static const online = Color(0xFF2E7D32);
  static const scheduled = Color(0xFF6D28D9);
  static const offline = Color(0xFF475569);

  static Color of(HostAvailability mode) => switch (mode) {
    HostAvailability.available => online,
    HostAvailability.custom => scheduled,
    HostAvailability.vacation => offline,
  };
}

/// Each mode's (Lucide) icon, the same in the dock's pill and this sheet.
abstract final class HostStatusIcons {
  static IconData of(HostAvailability mode) => switch (mode) {
    HostAvailability.available => LucideIcons.phoneCall,
    HostAvailability.custom => LucideIcons.calendarClock,
    HostAvailability.vacation => LucideIcons.power,
  };
}

/// "Host Availability": online / my working hours / offline (for good or for
/// a while), as a light bottom sheet for the signed-in host. Any choice
/// closes it at once; [HostAvailabilityController] saves behind it and the
/// dock's pill shows the new mode straight away. Working hours open the
/// schedule step, which sets the mode with the hours.
///
/// [source]: where it was opened from (analytics).
Future<void> showHostAvailabilitySheet(
  BuildContext context, {
  String source = 'unknown',
}) {
  HostEvents.availabilitySheetOpened(
    source: source,
    current: hostStatusName(
      HostAvailabilityController.current(
        MeData.of(SessionStore.instance.value),
      ),
    ),
  );
  return showModalBottomSheet<void>(
    context: context,
    routeSettings: ScreenTracker.sheet('host_availability_sheet'),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.transparent,
    barrierColor: AppColors.blackA(0.45),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 240),
      reverseDuration: Duration(milliseconds: 160),
    ),
    builder: (_) => const _HostAvailabilitySheet(),
  );
}

class _HostAvailabilitySheet extends StatelessWidget {
  const _HostAvailabilitySheet();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Read once: the sheet closes on any choice.
    final data = MeData.of(SessionStore.instance.value);
    final mode = HostAvailabilityController.current(data);
    final router = GoRouter.of(context);
    final summary = scheduleSummary(data.host);

    void choose(Future<void> Function() action) {
      unawaited(HapticFeedback.selectionClick());
      Navigator.of(context).pop();
      unawaited(action());
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        16.ms,
        8.ms,
        16.ms,
        12.ms + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.modalCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.ms)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40.ms,
                height: 4.ms,
                margin: EdgeInsets.only(bottom: 12.ms),
                decoration: BoxDecoration(
                  color: c.text.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2.ms),
                ),
              ),
            ),
            CText(
              'client:me.availability.sheet.title',
              size: 16,
              weight: FontWeight.w900,
              color: c.text,
            ),
            SizedBox(height: 2.ms),
            CText(
              'client:me.availability.sheet.subtitle',
              size: 12,
              weight: FontWeight.w600,
              color: c.textMuted,
            ),
            SizedBox(height: 12.ms),
            _Option(
              tone: HostStatusColors.online,
              icon: HostStatusIcons.of(HostAvailability.available),
              title: 'client:me.availability.sheet.online_title',
              subtitle: const _Muted(
                'client:me.availability.sheet.online_desc',
              ),
              active: mode == HostAvailability.available,
              onTap: () => choose(
                () => HostAvailabilityController.set(
                  HostAvailability.available,
                  source: 'availability_sheet',
                ),
              ),
            ),
            SizedBox(height: 8.ms),
            _Option(
              tone: HostStatusColors.scheduled,
              icon: HostStatusIcons.of(HostAvailability.custom),
              title: 'client:me.availability.sheet.schedule_title',
              subtitle: summary == null
                  ? const _Muted('client:me.availability.sheet.schedule_unset')
                  : CText(
                      'client:me.availability.sheet.hours',
                      variables: {
                        'start': summary.start,
                        'end': summary.end,
                        'days': summary.days,
                      },
                      size: 12,
                      weight: FontWeight.w700,
                      color: c.textMuted,
                      maxLines: 1,
                    ),
              active: mode == HostAvailability.custom,
              trailing: LucideIcons.chevronRight,
              onTap: () => choose(() async {
                HostEvents.workingHoursTapped();
                await router.push<void>(AppRoutes.hostSchedule);
                MeActions.revalidate();
              }),
            ),
            SizedBox(height: 8.ms),
            _Option(
              tone: HostStatusColors.offline,
              icon: HostStatusIcons.of(HostAvailability.vacation),
              title: 'client:me.availability.sheet.offline_title',
              subtitle: const _OfflineStatus(),
              active: mode == HostAvailability.vacation,
              onTap: () => choose(
                () => HostAvailabilityController.goOffline(
                  null,
                  source: 'availability_sheet',
                ),
              ),
              footer: _Durations(
                onPick: (d, label) => choose(
                  () => HostAvailabilityController.goOffline(
                    d,
                    durationLabel: label,
                    source: 'availability_sheet',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One mode: icon, title, a line under it and a check when it is on. No
/// animation or shadow: the sheet closes on the tap anyway.
class _Option extends StatelessWidget {
  const _Option({
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
    this.trailing,
    this.footer,
  });

  final Color tone;
  final IconData icon;
  final String title;
  final Widget subtitle;
  final bool active;
  final VoidCallback onTap;

  /// Shown when not [active] (e.g. a chevron: the tap opens a screen).
  final IconData? trailing;

  /// Below the row, outside its tap (the offline durations).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final end = active ? LucideIcons.circleCheck : trailing;
    return Container(
      padding: EdgeInsets.all(12.ms),
      decoration: BoxDecoration(
        color: active
            ? tone.withValues(alpha: c.isDark ? 0.20 : 0.08)
            : c.text.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(
          width: active ? 1.5 : 1,
          color: active ? tone : c.text.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            activeOpacity: 0.6,
            onPressed: onTap,
            child: Row(
              children: [
                Container(
                  width: 36.ms,
                  height: 36.ms,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: c.isDark ? 0.28 : 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18.ms, color: tone),
                ),
                SizedBox(width: 12.ms),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CText(
                        title,
                        size: 14,
                        weight: FontWeight.w800,
                        color: c.text,
                        maxLines: 1,
                      ),
                      SizedBox(height: 2.ms),
                      subtitle,
                    ],
                  ),
                ),
                if (end != null) ...[
                  SizedBox(width: 8.ms),
                  Icon(end, size: 20.ms, color: active ? tone : c.textMuted),
                ],
              ],
            ),
          ),
          if (footer != null) ...[SizedBox(height: 10.ms), footer!],
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => CText(
    text,
    size: 12,
    height: 16,
    color: context.colors.textMuted,
    maxLines: 2,
  );
}

/// "Pause calls until you switch back", or the live "Back online in 29m 10s"
/// while an offline timer runs.
class _OfflineStatus extends StatelessWidget {
  const _OfflineStatus();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration?>(
    valueListenable: HostAvailabilityController.remaining,
    builder: (_, left, _) => left == null
        ? const _Muted('client:me.availability.sheet.offline_desc')
        : CText(
            'client:me.availability.sheet.back_in',
            variables: {'time': formatOfflineLeft(left)},
            size: 12,
            weight: FontWeight.w800,
            color: context.colors.text,
            maxLines: 1,
          ),
  );
}

/// Offline for a while: back online on its own after the picked time.
class _Durations extends StatelessWidget {
  const _Durations({required this.onPick});

  /// The duration and its analytics name.
  final void Function(Duration duration, String label) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = [
      (
        'client:me.availability.sheet.for_30m',
        const Duration(minutes: 30),
        '30m',
      ),
      ('client:me.availability.sheet.for_1h', const Duration(hours: 1), '1h'),
      ('client:me.availability.sheet.for_2h', const Duration(hours: 2), '2h'),
      (
        'client:me.availability.sheet.till_morning',
        HostAvailabilityController.untilMorning(),
        'till_9am',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CText(
          'client:me.availability.sheet.timed',
          size: 11,
          weight: FontWeight.w700,
          color: c.textMuted,
        ),
        SizedBox(height: 6.ms),
        Wrap(
          spacing: 6.ms,
          runSpacing: 6.ms,
          children: [
            for (final (label, duration, name) in options)
              Pressable(
                activeOpacity: 0.6,
                onPressed: () => onPick(duration, name),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 11.ms,
                    vertical: 6.ms,
                  ),
                  decoration: BoxDecoration(
                    color: c.modalCard,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.text.withValues(alpha: 0.14)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.timer, size: 13.ms, color: c.textMuted),
                      SizedBox(width: 4.ms),
                      CText(
                        label,
                        size: 11.5,
                        weight: FontWeight.w800,
                        color: c.text,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// "09:00 AM", "06:00 PM" and the number of days with hours: the earliest
/// start and latest end across the week. Null when no hours are set.
({String start, String end, int days})? scheduleSummary(HostProfile? host) {
  final week = host?.weeklySchedule;
  if (week == null) return null;
  int? start;
  int? end;
  var days = 0;
  for (final slots in week.values) {
    if (slots.isEmpty) continue;
    days++;
    for (final s in slots) {
      if (start == null || s.startMinutes < start) start = s.startMinutes;
      if (end == null || s.endMinutes > end) end = s.endMinutes;
    }
  }
  if (days == 0 || start == null || end == null) return null;
  return (start: _clock(start), end: _clock(end), days: days);
}

String _clock(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final mm = m.toString().padLeft(2, '0');
  return '${h12.toString().padLeft(2, '0')}:$mm ${h24 < 12 ? 'AM' : 'PM'}';
}
