import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/profile_models.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/image_preview_modal.dart';
import '../../../component/pressable.dart';
import '../helper/me_actions.dart';
import '../helper/me_data.dart';
import '../helper/me_palette.dart';

/// Avatar (tap: preview with share / copy link / QR), name, handle, and the
/// account line: company chip, host availability pill, or "General User".
class MeProfileCard extends StatelessWidget {
  const MeProfileCard({super.key, required this.data});
  final MeData data;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final name = data.name ?? context.t('client:fallback.user_name');
    return Container(
      margin: EdgeInsets.only(top: 6.ms),
      padding: EdgeInsets.fromLTRB(18.ms, 28.ms, 18.ms, 16.ms),
      decoration: BoxDecoration(
        color: p.profileBg,
        borderRadius: BorderRadius.circular(32.ms),
        border: Border.all(color: p.profileBorder),
      ),
      child: Column(
        children: [
          Pressable(
            activeOpacity: 0.9,
            semanticLabel: context.t('client:me.avatar'),
            onPressed: () => _preview(context, name),
            child: _Avatar(data: data, name: name),
          ),
          SizedBox(height: 14.ms),
          CText.raw(
            name,
            variant: CTextVariant.h2,
            color: p.text,
            align: TextAlign.center,
            maxLines: 2,
          ),
          if (data.handler != null)
            Padding(
              padding: EdgeInsets.only(top: 3.ms),
              child: CText.raw('@${data.handler}', color: p.muted, maxLines: 1),
            ),
          if (data.isCompany)
            const _CompanyChip()
          else if (data.isExpert)
            _ModePill(mode: data.availability)
          else
            Padding(
              padding: EdgeInsets.only(top: 8.ms),
              child: CText(
                'client:me.general_user',
                size: 13,
                weight: FontWeight.w600,
                color: p.muted,
              ),
            ),
        ],
      ),
    );
  }

  void _preview(BuildContext context, String name) {
    final link = data.previewLink;
    // Built now: the actions run after the preview has closed.
    final message = link == null
        ? null
        : context.t('client:me.share.my_message', variables: {'link': link});
    ImagePreviewModal.show(
      context,
      imageUrl: data.avatarUrl,
      title: name,
      handle: data.handler ?? '',
      onShare: message == null ? null : () => MeActions.share(message),
      onCopyLink: link == null
          ? null
          : () async {
              await MeActions.copy(link);
              CToast.show(
                'client:me.share.link_copied',
                variant: CToastVariant.success,
              );
            },
      onShowQR: () {
        if (context.mounted) MeActions.open(context, AppRoutes.profileQr);
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.data, required this.name});
  final MeData data;
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final dot = switch (data.status) {
      MeStatus.online => BrandColors.vibeLime,
      MeStatus.busy => AppColors.logoutRed,
      MeStatus.offline => p.offline,
    };
    return SizedBox.square(
      dimension: 116.ms,
      child: Stack(
        children: [
          Container(
            width: 116.ms,
            height: 116.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.avatarBg,
              shape: BoxShape.circle,
              border: Border.all(color: p.accent, width: 2),
            ),
            child: CAvatar(url: data.avatarUrl, name: name, size: 116.ms - 4),
          ),
          // Hosts only: a client has no call status to report.
          if (data.isExpert)
            Positioned(
              right: 3,
              bottom: 3,
              child: Container(
                width: 22.ms,
                height: 22.ms,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.dotBorder, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode});
  final HostAvailability mode;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final dark = p.isDark;
    final (bg, dot, label) = switch (mode) {
      HostAvailability.vacation => (
        dark
            ? AvailabilityColors.vacationPillDark
            : AvailabilityColors.vacationPillLight,
        AvailabilityColors.vacationDot,
        'client:me.mode.vacation',
      ),
      HostAvailability.available => (
        dark
            ? AvailabilityColors.availablePillDark
            : AvailabilityColors.availablePillLight,
        AvailabilityColors.availableDot,
        'client:me.mode.available',
      ),
      HostAvailability.custom => (
        dark
            ? AvailabilityColors.customPillDark
            : AvailabilityColors.customPillLight,
        AvailabilityColors.customDot,
        'client:me.mode.custom',
      ),
    };
    return Container(
      margin: EdgeInsets.only(top: 10.ms),
      padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 7.ms),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9.ms,
            height: 9.ms,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          SizedBox(width: 8.ms),
          Flexible(
            child: CText(
              label,
              size: 14,
              weight: FontWeight.w700,
              color: p.pillText,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyChip extends StatelessWidget {
  const _CompanyChip();

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(top: 10.ms),
    padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 4.ms),
    decoration: BoxDecoration(
      color: MeColors.companyBg,
      borderRadius: BorderRadius.circular(12.ms),
      border: Border.all(color: MeColors.companyBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.business, size: 16.ms, color: MeColors.companyText),
        SizedBox(width: 5.ms),
        const Flexible(
          child: CText(
            'client:me.company_profile',
            size: 13,
            weight: FontWeight.w600,
            color: MeColors.companyText,
            maxLines: 1,
          ),
        ),
      ],
    ),
  );
}
