import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/query/query_client.dart';
import '../../../../core/query/query_persist.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/hosthub_keys.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/stats_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/me_actions.dart';
import '../helper/me_palette.dart';
import 'me_rows.dart';
import 'referral_invite_card.dart';

typedef _Tile = ({
  IconData icon,
  Color tint,
  String label,
  String value,
  Color? valueTint,
});

/// The host's numbers (RN `HostDashboard`), as a sliver: lifetime earnings,
/// the invite card, four stat sections and the referral programme row.
/// Figures paint from the disk copy and refresh in place; before the first
/// ever load the tiles show zeros and the headline a shimmer.
class MeHostDashboard extends HookWidget {
  const MeHostDashboard({super.key, this.footer});

  /// Last item: the call rates / availability chips.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    // Query ticks reach only the zero-size watcher; the list rebuilds when
    // the figures (or the first-load flag) actually change.
    final stats = useValueNotifier<_Stats>(_cachedStats());
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _StatsWatcher(out: stats)),
        ValueListenableBuilder<_Stats>(
          valueListenable: stats,
          builder: (_, v, _) =>
              _DashboardList(stats: v.s, loading: v.loading, footer: footer),
        ),
      ],
    );
  }
}

typedef _Stats = ({HostStats s, bool loading});

/// The stats already in memory or on disk (no first-frame zeros).
_Stats _cachedStats() {
  final id = SessionStore.instance.value.userDocumentId;
  if (id == null) return (s: HostStats.empty, loading: true);
  final key = HostHubKeys.stats(id);
  final data =
      queryCache.getQueryData<HostStats, ApiException>(key) ??
      QueryPersist.read<HostStats>(key, HostStats.fromJson);
  return (s: data ?? HostStats.empty, loading: data == null);
}

/// Owns the stats query; pushes changes after the frame.
class _StatsWatcher extends HookWidget {
  const _StatsWatcher({required this.out});
  final ValueNotifier<_Stats> out;

  @override
  Widget build(BuildContext context) {
    final query = useHostStats(context);
    final next = (
      s: query.data ?? HostStats.empty,
      loading: query.data == null && !query.isError,
    );
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = out.value;
        if (!identical(now.s, next.s) || now.loading != next.loading) {
          out.value = next;
        }
      });
      return null;
    }, [query.data, query.isError]);
    return const SizedBox.shrink();
  }
}

class _DashboardList extends StatelessWidget {
  const _DashboardList({
    required this.stats,
    required this.loading,
    this.footer,
  });

  final HostStats stats;
  final bool loading;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final s = stats;

    String duration(double minutes) {
      final d = HostStats.splitMinutes(minutes);
      return context.t(
        'client:me.stats.duration',
        variables: {'minutes': d.minutes, 'seconds': d.seconds},
      );
    }

    const views = BrandColors.teal;
    final rose = p.accent;
    const lime = BrandColors.lime;
    const negative = AppColors.logoutRed;
    const count = HostStats.formatNumber;
    const money = HostStats.formatCurrency;
    const pct = HostStats.formatPercent;

    _Tile tile(
      IconData icon,
      Color tint,
      String label,
      String value, [
      Color? valueTint,
    ]) => (
      icon: icon,
      tint: tint,
      label: 'client:me.stats.$label',
      value: value,
      valueTint: valueTint,
    );

    final sections = <(String, List<_Tile>)>[
      (
        'insights',
        [
          tile(LucideIcons.eye, views, 'profile_views', count(s.profileViews)),
          tile(
            LucideIcons.star,
            lime,
            'avg_rating',
            s.averageRating.toStringAsFixed(1),
          ),
          tile(LucideIcons.users, rose, 'referrals', count(s.totalReferrals)),
          tile(LucideIcons.activity, views, 'conversion', pct(s.conversion)),
          tile(
            LucideIcons.phoneMissed,
            negative,
            'missed_calls',
            pct(s.missedCallPct),
            negative,
          ),
          tile(
            LucideIcons.phoneOff,
            negative,
            'declined',
            pct(s.declinedCallPct),
            negative,
          ),
        ],
      ),
      (
        'revenue',
        [
          tile(LucideIcons.wallet, lime, 'withdrawals', money(s.withdrawals)),
          tile(
            LucideIcons.video,
            lime,
            'video_earning',
            money(s.videoEarnings),
          ),
          tile(
            LucideIcons.phoneIncoming,
            lime,
            'audio_earning',
            money(s.audioEarnings),
          ),
          tile(
            LucideIcons.gift,
            rose,
            'referral_earning',
            money(s.referralEarnings),
          ),
        ],
      ),
      (
        'call_stats',
        [
          tile(
            LucideIcons.timer,
            views,
            'avg_duration_in',
            duration(s.avgIncomingMinutes),
          ),
          tile(
            LucideIcons.timer,
            views,
            'avg_duration_out',
            duration(s.avgOutgoingMinutes),
          ),
          tile(
            LucideIcons.phoneIncoming,
            views,
            'audio_calls',
            count(s.audioCalls),
          ),
          tile(
            LucideIcons.video,
            views,
            'video_minutes',
            context.t(
              'client:me.stats.minutes',
              variables: {'value': count(s.videoMinutes)},
            ),
          ),
        ],
      ),
      (
        'retention',
        [
          tile(
            LucideIcons.repeat,
            rose,
            'repeat_users_pct',
            pct(s.repeatCallerPct),
            rose,
          ),
          tile(LucideIcons.repeat, rose, 'repeat_calls', count(s.repeatCalls)),
          tile(LucideIcons.users, rose, 'repeat_users', count(s.repeatCallers)),
          tile(
            LucideIcons.activity,
            rose,
            'repeat_calls_pct',
            pct(s.repeatCallPct),
            rose,
          ),
        ],
      ),
    ];

    final gap = SizedBox(width: 10.ms);
    return SliverList.list(
      children: [
        _EarningsCard(stats: s, loading: loading),
        const MeReferralInviteCard(),
        for (final (title, tiles) in sections) ...[
          Padding(
            padding: EdgeInsets.only(top: 18.ms, bottom: 10.ms),
            child: CText(
              'client:me.stats.$title',
              size: 10,
              weight: FontWeight.w900,
              letterSpacing: 1.8,
              color: p.muted,
            ),
          ),
          for (var i = 0; i < tiles.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: 10.ms),
              child: Row(
                children: [
                  Expanded(child: _StatTile(tiles[i])),
                  gap,
                  Expanded(
                    child: i + 1 < tiles.length
                        ? _StatTile(tiles[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
        Padding(
          padding: EdgeInsets.only(top: 8.ms),
          child: MeSettingsCard(
            icon: LucideIcons.award,
            color: p.accent,
            title: 'client:me.stats.referral_program',
            subtitle: 'client:me.stats.referral_program_hint',
            chevron: false,
            onTap: () {
              HostEvents.dashboardReferralTapped();
              MeActions.open(context, AppRoutes.referral);
            },
          ),
        ),
        ?footer,
      ],
    );
  }
}

/// Lifetime earnings headline; tapping goes to the wallet, where the money
/// lives.
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.stats, required this.loading});
  final HostStats stats;
  final bool loading;

  /// The card is dark in both modes: its shimmer must be too.
  static final _dark = AppTheme.dark();

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final label = AppColors.whiteA(0.5);
    return Pressable(
      activeOpacity: 0.85,
      onPressed: () {
        HostEvents.earningsCardTapped();
        MeActions.open(context, AppRoutes.wallet);
      },
      child: Container(
        margin: EdgeInsets.only(top: 14.ms),
        padding: EdgeInsets.all(20.ms),
        decoration: BoxDecoration(
          color: p.earningsBg,
          borderRadius: BorderRadius.circular(28.ms),
          border: Border.all(color: p.cardBorder),
        ),
        child: Row(
          children: [
            const MeIconBox(
              color: BrandColors.lime,
              icon: LucideIcons.trendingUp,
              size: 48,
              radius: 16,
              iconSize: 22,
            ),
            SizedBox(width: 16.ms),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CText(
                    'client:me.stats.lifetime_earnings',
                    size: 10,
                    weight: FontWeight.w800,
                    letterSpacing: 1.6,
                    color: label,
                    maxLines: 1,
                  ),
                  SizedBox(height: 2.ms),
                  SizedBox(
                    height: 34.ms,
                    child: loading
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Theme(
                              data: _dark,
                              child: RepaintBoundary(
                                child: Shimmer(
                                  child: SkeletonBox(
                                    width: 110.ms,
                                    height: 24.ms,
                                    radius: 8,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: CText.raw(
                              HostStats.formatCurrency(stats.totalEarnings),
                              size: 28,
                              weight: FontWeight.w900,
                              letterSpacing: -1,
                              color: AppColors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.ms),
            // A big count shrinks instead of squeezing the earnings.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 96.ms),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CText(
                    'client:me.stats.calls',
                    size: 9,
                    weight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: label,
                    maxLines: 1,
                  ),
                  SizedBox(height: 2.ms),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: CText.raw(
                      HostStats.formatNumber(stats.totalCalls),
                      size: 18,
                      weight: FontWeight.w900,
                      color: AppColors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.tile);
  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    return Container(
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(20.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MeIconBox(
                color: tile.tint,
                icon: tile.icon,
                size: 28,
                radius: 9,
                iconSize: 15,
              ),
              SizedBox(width: 7.ms),
              Expanded(
                child: CText(
                  tile.label,
                  size: 9,
                  weight: FontWeight.w800,
                  letterSpacing: 0.8,
                  uppercase: true,
                  color: p.muted,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.ms),
          SizedBox(
            height: 24.ms,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CText.raw(
                tile.value,
                size: 19,
                weight: FontWeight.w900,
                letterSpacing: -0.4,
                color: tile.valueTint ?? p.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
