import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/profile_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../onboarding/helper/host_palette.dart';

/// Call rates and availability as one row of chips (wrapping only when
/// they don't fit); each opens its edit screen.
class HostInfoChips extends StatelessWidget {
  const HostInfoChips({super.key, required this.host, required this.open});

  final HostProfile host;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context) {
    final rates = host.rates;
    String perMin(double v) =>
        context.t('hostflow:preview.per_min', variables: {'amount': v.round()});
    final chips = [
      if (rates.voiceCallRate > 0)
        (
          icon: LucideIcons.headphones,
          text: perMin(rates.voiceCallRate),
          route: AppRoutes.callRates,
        ),
      if (rates.videoCallRate > 0)
        (
          icon: LucideIcons.video,
          text: perMin(rates.videoCallRate),
          route: AppRoutes.callRates,
        ),
      (
        icon: switch (host.availability) {
          HostAvailability.vacation => LucideIcons.plane,
          HostAvailability.available => LucideIcons.phoneCall,
          HostAvailability.custom => LucideIcons.calendarDays,
        },
        text: context.t(switch (host.availability) {
          HostAvailability.vacation => 'hostflow:hub.mode_vacation',
          HostAvailability.available => 'hostflow:hub.mode_available',
          HostAvailability.custom => 'hostflow:hub.mode_custom',
        }),
        route: AppRoutes.schedule,
      ),
    ];
    return Padding(
      padding: EdgeInsets.only(top: 14.ms),
      child: Wrap(
        spacing: 8.ms,
        runSpacing: 8.ms,
        children: [
          for (final c in chips)
            _Chip(icon: c.icon, text: c.text, onTap: () => open(c.route)),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Pressable(
      onPressed: onTap,
      child: Container(
        height: 36.ms,
        padding: EdgeInsets.symmetric(horizontal: 12.ms),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15.ms, color: p.accent),
            SizedBox(width: 6.ms),
            CText.raw(
              text,
              size: 13,
              weight: FontWeight.w700,
              color: p.text,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
