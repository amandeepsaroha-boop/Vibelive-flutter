import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/availability_change.dart';
import '../helper/me_actions.dart';
import '../helper/me_data.dart';
import '../helper/me_palette.dart';
import 'me_segmented.dart';

/// "AVAILABILITY MODES": available / vacation / custom, with labels and a
/// hint. The compact, icon-only form is [AvailabilitySwitcher].
class MeAvailabilityCard extends HookWidget {
  const MeAvailabilityCard({super.key, required this.data});
  final MeData data;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final availability = useAvailabilityChange(context, data);
    final mode = availability.mode;

    final hint = availability.saving
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
            segments: availabilitySegments,
            selected: mode,
            enabled: !availability.saving,
            onSelect: availability.change,
          ),
          SizedBox(height: 9.ms),
          CText(hint, size: 11, color: p.muted, align: TextAlign.center),
        ],
      ),
    );
  }
}
