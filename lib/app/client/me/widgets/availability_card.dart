import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_keys.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../api/hosthub/profile_patch.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/me_actions.dart';
import '../helper/me_data.dart';
import '../helper/me_palette.dart';
import 'me_segmented.dart';

const _modes = [
  MeSegment(
    HostAvailability.available,
    LucideIcons.phoneCall,
    'client:me.availability.available',
  ),
  MeSegment(
    HostAvailability.vacation,
    LucideIcons.plane,
    'client:me.availability.vacation',
  ),
  MeSegment(
    HostAvailability.custom,
    LucideIcons.settings2,
    'client:me.availability.custom',
  ),
];

/// "AVAILABILITY MODES": available / vacation / custom (RN
/// `handleMeAvailabilityModeChange`). The tapped mode is shown at once while
/// it saves; custom without a saved slot opens the schedule.
class MeAvailabilityCard extends HookWidget {
  const MeAvailabilityCard({super.key, required this.data});
  final MeData data;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    // The save re-reads the profile into the session, which re-renders this
    // card with the new mode; the client profile is re-read too.
    final update = useUpdateHostProfile(
      alsoInvalidate: const [ClientKeys.profiles],
    );
    final pending = useState<HostAvailability?>(null);
    final mode = pending.value ?? data.availability;

    Future<void> change(HostAvailability next) async {
      if (pending.value != null) return;
      final expertId = data.expertId;
      if (expertId == null) {
        await CAlert.show(
          title: 'client:me.availability.error_title',
          message: 'client:me.availability.no_profile',
          variant: CAlertVariant.warning,
        );
        return;
      }
      final needsSchedule = !data.hasScheduleSlots;
      if (next == data.availability &&
          !(next == HostAvailability.custom && needsSchedule)) {
        return;
      }
      pending.value = next;
      try {
        final saved = await update.mutateAsync((
          expertId: expertId,
          patch: HostProfilePatch.availability(next),
        ));
        if (!context.mounted) return;
        final hasSlots = saved == null
            ? data.hasScheduleSlots
            : MeData.hasSlots(saved);
        if (next == HostAvailability.custom && !hasSlots) {
          await MeActions.open(context, AppRoutes.schedule);
        }
      } on ApiException catch (e) {
        await CAlert.error(e, title: 'client:me.availability.error_title');
      } finally {
        if (context.mounted) pending.value = null;
      }
    }

    final hint = pending.value != null
        ? 'client:me.availability.updating'
        : switch (mode) {
            HostAvailability.vacation => 'client:me.availability.hint_vacation',
            HostAvailability.available =>
              'client:me.availability.hint_available',
            HostAvailability.custom =>
              data.hasScheduleSlots
                  ? 'client:me.availability.hint_custom'
                  : 'client:me.availability.hint_custom_unset',
          };

    return Container(
      margin: EdgeInsets.only(top: 12.ms),
      padding: EdgeInsets.all(12.ms),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(22.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: CText(
                  'client:me.availability.title',
                  size: 11,
                  weight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: p.text,
                  maxLines: 1,
                ),
              ),
              Pressable(
                activeOpacity: 0.8,
                hitPadding: EdgeInsets.all(6.ms),
                onPressed: () => MeActions.open(context, AppRoutes.schedule),
                child: CText(
                  'client:me.availability.manage',
                  size: 11,
                  weight: FontWeight.w700,
                  color: p.accent,
                ),
              ),
            ],
          ),
          SizedBox(height: 4.ms),
          MeSegmented<HostAvailability>(
            segments: _modes,
            selected: mode,
            enabled: pending.value == null,
            onSelect: change,
          ),
          SizedBox(height: 9.ms),
          CText(hint, size: 11, color: p.muted, align: TextAlign.center),
        ],
      ),
    );
  }
}
