import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../listingflow/profile/helper/host_profile_controller.dart';
import '../../../listingflow/profile/profile_about.dart';
import '../../../listingflow/profile/profile_gallery.dart';
import '../../../listingflow/profile/profile_header.dart';
import '../../../api/hosthub/profile_models.dart';
import '../helper/draft_controller.dart';
import '../helper/host_palette.dart';
import '../helper/host_steps.dart';
import '../helper/preview_card.dart';
import '../helper/schedule_format.dart';
import '../helper/validation.dart';
import '../widgets/day_schedule_row.dart';
import '../widgets/preview_sections.dart';
import '../widgets/step_body.dart';

/// 9 of 11: the profile exactly as clients see it, drawn by the client
/// profile sheet's own widgets (gallery, header, about, specialization)
/// from the draft. Each block has an Edit link that opens its step and
/// comes back here; empty blocks are hidden.
class PreviewStep extends HookWidget {
  const PreviewStep({super.key, required this.draft, required this.onEdit});
  final HostDraftController draft;
  final ValueChanged<HostStep> onEdit;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final controller = useMemoized(
      () => HostProfileController(
        close: () {},
        navigate: (_) {},
        confirmStart: (_) async => false,
        handOff: (_, _) async {},
      ),
    );
    useEffect(() => controller.dispose, [controller]);
    return ListenableBuilder(
      listenable: Listenable.merge([
        d.photos,
        d.voiceIntro,
        d.topics,
        d.languages,
        d.district,
        d.availableNow,
        d.vacation,
        d.week,
        d.audioOn,
        d.videoOn,
        d.audioRate,
        d.videoRate,
      ]),
      builder: (context, _) => HostStepBody(
        title: 'hostflow:preview.title',
        subtitle: 'hostflow:preview.subtitle',
        children: [_sheet(context, controller)],
      ),
    );
  }

  Widget _sheet(BuildContext context, HostProfileController controller) {
    final d = draft;
    final c = context.colors;
    final host = previewHostCard(d);
    final width = MediaQuery.sizeOf(context).width;
    final hero = math.min((width * 1.1).roundToDouble(), 420.0);
    final hasAbout = host.tagline.isNotEmpty || host.description.isNotEmpty;
    final rates = HostValidation.ratesOf(d);
    // RN: the weekly slots apply only when neither mode above is on.
    final days = [
      if (d.mode == HostAvailability.custom)
        for (final e in d.week.value.entries)
          if (e.value.slots.isNotEmpty) e,
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(22.ms),
      child: ColoredBox(
        color: profileCardColor(c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Editable(
              keyName: 'photos',
              onEdit: () => onEdit(HostStep.photos),
              child: ProfileGallery(
                host: host,
                height: hero,
                topInset: 0,
                controller: controller,
                canFavorite: false,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, 6.ms),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileHeader(
                    host: host,
                    showCompany: false,
                    onInfluencer: () {},
                  ),
                  if (d.vacation.value || d.availableNow.value)
                    Padding(
                      padding: EdgeInsets.only(bottom: 12.ms),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _AvailabilityPill(away: d.vacation.value),
                      ),
                    ),
                  if (hasAbout)
                    _Editable(
                      keyName: 'about',
                      onEdit: () => onEdit(
                        host.tagline.isEmpty ? HostStep.bio : HostStep.tagline,
                      ),
                      child: ProfileVibeCard(host: host),
                    ),
                  if (host.tags.isNotEmpty || host.languages.isNotEmpty)
                    _Editable(
                      keyName: 'topics',
                      onEdit: () => onEdit(
                        host.tags.isEmpty ? HostStep.basic : HostStep.interests,
                      ),
                      child: ProfileSpecializationCard(host: host),
                    ),
                  if (rates.hasAny)
                    PreviewSection(
                      title: 'hostflow:preview.rates',
                      onEdit: () => onEdit(HostStep.rates),
                      child: Column(
                        children: [
                          if (rates.voiceCallRate > 0)
                            PreviewLine(
                              icon: LucideIcons.headphones,
                              text: context.t('hostflow:rates.audio'),
                              trailing: context.t(
                                'hostflow:preview.per_min',
                                variables: {
                                  'amount': rates.voiceCallRate.round(),
                                },
                              ),
                            ),
                          if (rates.videoCallRate > 0)
                            PreviewLine(
                              icon: LucideIcons.video,
                              text: context.t('hostflow:rates.video'),
                              trailing: context.t(
                                'hostflow:preview.per_min',
                                variables: {
                                  'amount': rates.videoCallRate.round(),
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  PreviewSection(
                    title: 'hostflow:preview.availability',
                    onEdit: () => onEdit(HostStep.availability),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (d.vacation.value)
                          PreviewLine(
                            icon: LucideIcons.plane,
                            text: context.t('hostflow:preview.vacation'),
                          )
                        else ...[
                          if (d.availableNow.value)
                            PreviewLine(
                              icon: LucideIcons.radio,
                              text: context.t('hostflow:preview.any_time'),
                            ),
                          for (final e in days)
                            PreviewLine(
                              icon: LucideIcons.calendarDays,
                              text: context.t(HostScheduleFormat.dayKey(e.key)),
                              trailing: [
                                for (final slot in e.value.slots)
                                  hostRangeLabel(context, slot),
                              ].join('\n'),
                            ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 10.ms),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A profile block with an "Edit" chip in its top-right corner.
class _Editable extends StatelessWidget {
  const _Editable({
    required this.keyName,
    required this.onEdit,
    required this.child,
  });

  final String keyName;
  final VoidCallback onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Stack(
      children: [
        child,
        Positioned(
          top: 10.ms,
          right: 10.ms,
          child: Pressable(
            key: ValueKey('preview-edit-$keyName'),
            onPressed: onEdit,
            hitPadding: EdgeInsets.all(6.ms),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 5.ms),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.pencil, size: 12.ms, color: p.accent),
                  SizedBox(width: 4.ms),
                  CText(
                    'hostflow:preview.edit',
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The ME tab's availability pill (same `AvailabilityColors`): Online when
/// taking calls now, On vacation when calls are paused.
class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({required this.away});
  final bool away;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    final (bg, dot, label) = away
        ? (
            dark
                ? AvailabilityColors.vacationPillDark
                : AvailabilityColors.vacationPillLight,
            AvailabilityColors.vacationDot,
            'hostflow:review.vacation',
          )
        : (
            dark
                ? AvailabilityColors.availablePillDark
                : AvailabilityColors.availablePillLight,
            AvailabilityColors.availableDot,
            'hostflow:review.online',
          );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 6.ms),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8.ms,
            height: 8.ms,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          SizedBox(width: 7.ms),
          CText(
            label,
            size: 12.5,
            weight: FontWeight.w800,
            color: dark ? AppColors.white : dot,
          ),
        ],
      ),
    );
  }
}
