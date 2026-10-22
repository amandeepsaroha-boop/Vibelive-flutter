import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_models.dart';
import '../../api/client/client_queries.dart';
import '../../api/client/referral_api.dart';
import '../../component/app_share.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/c_toast.dart';
import '../../component/infinite_scroll.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import 'helper/referral_format.dart';
import 'helper/referral_palette.dart';
import 'widgets/referral_header.dart';
import 'widgets/referral_skeleton.dart';
import 'widgets/referral_summary.dart';
import 'widgets/referred_user_tile.dart';

/// Referral programme (RN `ReferralScreen`, `/me/referral`): the user's code
/// and `?r=r` link, the share counter, and who joined with the code.
class ReferralScreen extends HookWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    final query = useReferralDashboard(context);
    final refreshing = useValueNotifier(false);
    final sharing = useValueNotifier(false);
    final track = useTrackReferralShare(type: ReferralShareType.referral);

    // Refresh button and pull-to-refresh (RN `loadData({silent: true})`):
    // a failure keeps what is shown and says why.
    Future<void> refresh() async {
      if (refreshing.value) return;
      refreshing.value = true;
      try {
        await ensureReferralDashboard();
      } on ApiException catch (e) {
        CToast.error(e);
      } finally {
        if (context.mounted) refreshing.value = false;
      }
    }

    Future<void> share() async {
      if (sharing.value) return;
      final code = query.data?.referralCode ?? '';
      if (code.isEmpty) {
        await CAlert.show(
          title: 'client:referral.alert_title',
          message: 'client:referral.code_unavailable',
        );
        return;
      }
      sharing.value = true;
      try {
        await AppShare.text(
          ReferralFormat.link(code),
          subject: context.t('client:referral.share_subject'),
        );
        // Counting is best effort (RN): show the backend's count, or one more
        // when the count fails. A success also re-reads the dashboard.
        try {
          final count = await track.mutateAsync(code);
          if (count != null) bumpReferralClicks(count);
        } on ApiException {
          bumpReferralClicks(null);
        }
      } finally {
        if (context.mounted) sharing.value = false;
      }
    }

    final data = query.data;
    final error = query.error;
    final Widget body;
    if (data != null) {
      body = _ReferralList(
        data: data,
        sharing: sharing,
        onShare: share,
        onRefresh: refresh,
      );
    } else if (query.isError && error != null) {
      body = CStateView.error(context, error, onRetry: query.refetch);
    } else {
      body = const ReferralSkeleton();
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ReferralHeader(refreshing: refreshing, onRefresh: refresh),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header card, counters and the referred users: one lazy scroll view with
/// fixed-height rows (RN FlatList with `ListHeaderComponent`).
class _ReferralList extends StatelessWidget {
  const _ReferralList({
    required this.data,
    required this.sharing,
    required this.onShare,
    required this.onRefresh,
  });

  final ReferralDashboard data;
  final ValueListenable<bool> sharing;
  final VoidCallback onShare;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final users = data.joinedUsers;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return InfiniteScroll(
      // RN reads one page of up to 100 users: nothing more to load.
      hasMore: false,
      loadingMore: false,
      onLoadMore: () {},
      onRefresh: onRefresh,
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 28.ms + bottom),
      slivers: [
        SliverToBoxAdapter(
          child: ReferralSummary(
            code: data.referralCode,
            totalClicks: data.totalClicks,
            joinedUserCount: data.joinedUserCount,
            sharing: sharing,
            onShare: onShare,
          ),
        ),
        if (users.isEmpty)
          const SliverToBoxAdapter(child: ReferralEmpty())
        else
          SliverFixedExtentList.builder(
            itemExtent: ReferredUserTile.extent.ms,
            itemCount: users.length,
            itemBuilder: (context, i) => ReferredUserTile(user: users[i]),
          ),
      ],
    );
  }
}
