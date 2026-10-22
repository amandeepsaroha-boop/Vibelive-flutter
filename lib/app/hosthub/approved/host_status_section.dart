import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/approval_models.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/profile_models.dart';
import '../common/moderation_banners.dart';
import 'widgets/go_online_card.dart';
import 'widgets/host_menu_card.dart';
import 'widgets/quick_stats.dart';
import 'widgets/review_status_card.dart';
import 'widgets/share_profile_card.dart';

/// The host's onboarding state on the ME tab, above the existing host
/// dashboard:
///  * approved but not live yet → the design's "first steps" panel (Go
///    online, share, quick stats, shortcuts); it stays for the visit once
///    shown, so going online doesn't yank it away;
///  * not approved → under review / changes needed / finish setup;
///  * live → nothing (the dashboard below covers it).
class HostStatusSection extends HookWidget {
  const HostStatusSection({
    super.key,
    required this.host,
    required this.open,
    required this.onShowDashboard,
    required this.onShowSettings,
    this.profileLink,
    this.name,
    this.email,
  });

  final HostProfile host;

  /// Opens a route (and refreshes ME on return).
  final Future<void> Function(String route) open;
  final VoidCallback onShowDashboard;
  final VoidCallback onShowSettings;
  final String? profileLink;
  final String? name;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final approved = host.isApproved;
    final pinned = useRef(false);
    if (approved && !host.isActive) pinned.value = true;

    Widget? child;
    if (approved) {
      if (pinned.value) child = _FirstSteps(section: this);
    } else {
      // Its own widget: approval-query ticks rebuild only the card.
      child = _ReviewStatus(host: host, open: open);
    }
    final hasNews = hostModerationNotices(host).isNotEmpty;
    if (child == null && !hasNews) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 12.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // RN MeModule: moderation news above everything else.
          if (hasNews) HostModerationBanners(host: host),
          ?child,
        ],
      ),
    );
  }
}

class _ReviewStatus extends HookWidget {
  const _ReviewStatus({required this.host, required this.open});
  final HostProfile host;
  final Future<void> Function(String route) open;

  @override
  Widget build(BuildContext context) {
    final latest = useLatestApproval(
      context,
      expertId: host.key,
      enabled: host.key.isNotEmpty,
    );
    if (latest.data == null && latest.isLoading) {
      return const SizedBox.shrink();
    }
    return HostReviewStatusCard(
      status: ApprovalRecord.effective(host, latest.data),
      onOpenFlow: () => open(AppRoutes.hostOnboarding),
    );
  }
}

class _FirstSteps extends StatelessWidget {
  const _FirstSteps({required this.section});
  final HostStatusSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final gap = SizedBox(height: 12.ms);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HostGoOnlineCard(
          expertId: s.host.key,
          active: s.host.isActive,
          name: s.name,
          email: s.email,
        ),
        if (s.profileLink != null) ...[
          gap,
          HostShareProfileCard(link: s.profileLink!),
        ],
        gap,
        const HostQuickStats(),
        gap,
        HostMenuCard(
          entries: [
            (
              icon: LucideIcons.calendarDays,
              label: 'hostflow:approved.schedule',
              onTap: () => s.open(AppRoutes.hostSchedule),
            ),
            (
              icon: LucideIcons.circleDollarSign,
              label: 'hostflow:approved.rates',
              onTap: () => s.open(AppRoutes.hostRates),
            ),
            (
              icon: LucideIcons.chartNoAxesColumn,
              label: 'hostflow:approved.analytics',
              onTap: s.onShowDashboard,
            ),
            (
              icon: LucideIcons.userRound,
              label: 'hostflow:approved.profile',
              onTap: () => s.open(AppRoutes.professionalDetails),
            ),
            (
              icon: LucideIcons.settings,
              label: 'hostflow:approved.settings',
              onTap: s.onShowSettings,
            ),
          ],
        ),
      ],
    );
  }
}
