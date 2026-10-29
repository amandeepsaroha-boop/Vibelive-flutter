import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/host_events.dart';
import '../../../core/router/app_router.dart';
import '../../api/hosthub/approval_models.dart';
import '../../api/hosthub/eligibility.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/profile_models.dart';
import '../../api/hosthub/verification_models.dart';
import '../onboarding/helper/host_palette.dart';
import 'hub_list.dart';

/// RN "HOST HUB" (menu-data `hub`, same order and labels) as one flat card:
/// every row opens its screen, and shows where the host stands at a glance.
class HostHubMenu extends StatelessWidget {
  const HostHubMenu({
    super.key,
    required this.host,
    required this.open,
    required this.verificationRoute,
    this.verificationPrompt,
  });

  final HostProfile host;
  final Future<void> Function(String route) open;

  /// RN: the fee screen, or the status once applied.
  final String verificationRoute;

  /// The "✨ APPLY FOR BADGE" pill, when there is something to do.
  final Widget? verificationPrompt;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final rates = host.rates;
    String rate(double v) => v > 0 ? '₹${v.round()}' : '–';
    final badge = HostEligibility.badgeStep(host.raw);

    final rows = <_Row>[
      (
        icon: LucideIcons.briefcase,
        label: 'client:me.items.pro_details',
        route: AppRoutes.professionalDetails,
        status: host.moderationStatus == 'pending_review'
            ? _status('hostflow:hub.in_review', p.warning)
            : null,
      ),
      (
        icon: LucideIcons.star,
        label: 'client:me.items.expertise',
        route: AppRoutes.expertise,
        status: null,
      ),
      (
        icon: LucideIcons.activity,
        label: 'client:me.items.schedule',
        route: AppRoutes.schedule,
        status: _status(switch (host.availability) {
          HostAvailability.vacation => 'hostflow:hub.mode_vacation',
          HostAvailability.available => 'hostflow:hub.mode_available',
          HostAvailability.custom => 'hostflow:hub.mode_custom',
        }, p.muted),
      ),
      (
        icon: LucideIcons.trendingUp,
        label: 'client:me.items.rates',
        route: AppRoutes.callRates,
        status: rates.hasAny
            ? _raw(
                '${rate(rates.voiceCallRate)} · ${rate(rates.videoCallRate)}',
                p.muted,
              )
            : null,
      ),
      (
        icon: LucideIcons.circleCheck,
        label: 'client:me.items.approval',
        route: AppRoutes.approval,
        status: _ApprovalStatusText(host: host),
      ),
      (
        icon: LucideIcons.award,
        label: 'client:me.items.verification',
        route: verificationRoute,
        status:
            verificationPrompt ??
            switch (badge) {
              VerificationStep.success => _status(
                'hostflow:hub.verified',
                p.success,
              ),
              VerificationStep.review => _status(
                'hostflow:hub.in_review',
                p.warning,
              ),
              _ => null,
            },
      ),
    ];

    return HubListCard(
      rows: [
        for (final r in rows)
          HubListRow(
            icon: r.icon,
            label: r.label,
            trailing: r.status,
            onTap: () {
              HostEvents.hubItemTapped(r.label.split('.').last);
              open(r.route);
            },
          ),
      ],
    );
  }

  static Widget _status(String key, Color color) =>
      HubListRow.status(key, color);

  static Widget _raw(String text, Color color) => HubListRow.value(text, color);
}

typedef _Row = ({IconData icon, String label, String route, Widget? status});

/// The approval row's status. Its own widget: the approval read (only for
/// a host not approved yet) rebuilds this text, never the card.
class _ApprovalStatusText extends HookWidget {
  const _ApprovalStatusText({required this.host});
  final HostProfile host;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final latest = useLatestApproval(
      context,
      expertId: host.key,
      enabled: !host.isApproved && host.key.isNotEmpty,
    );
    final (key, color) = switch (ApprovalRecord.effective(host, latest.data)) {
      ApprovalStatus.approved => (
        host.isActive ? 'hostflow:hub.live' : 'hostflow:hub.approved',
        p.success,
      ),
      ApprovalStatus.pending => ('hostflow:hub.pending', p.warning),
      ApprovalStatus.rejected => ('hostflow:hub.rejected', p.danger),
      null => (latest.isLoading ? null : 'hostflow:hub.not_sent', p.muted),
    };
    return key == null
        ? const SizedBox.shrink()
        : HostHubMenu._status(key, color);
  }
}
