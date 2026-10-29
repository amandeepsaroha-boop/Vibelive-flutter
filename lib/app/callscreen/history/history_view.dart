import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/callscreen/call_models.dart';
import '../../api/callscreen/call_queries.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../api/splashscreen/splash_queries.dart';
import '../../component/c_state_view.dart';
import '../../component/c_toast.dart';
import '../../component/infinite_scroll.dart';
import '../../homescreen/helper/home_controller.dart';
import '../../navbar/bottombar/navbar_collapse.dart';
import 'helper/history_entry.dart';
import 'helper/history_format.dart';
import 'helper/history_layout.dart';
import 'history_actions.dart';
import 'history_row.dart';
import 'history_skeleton.dart';

/// The History tab (RN `app/(tabs)/explore.jsx`): the LOGS header and the
/// paged call log. Page 1 renders from disk, later pages load on scroll, and
/// page 1 is refreshed quietly each time the tab is shown again.
class HistoryView extends HookWidget {
  const HistoryView({super.key, required this.home});
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final feed = useCallHistory(context);
    final pingConfig = useAppConfig(context).data?.expertPingConfig;
    final pingWindow = CallHistoryItem.pingWindow(pingConfig);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final entries = useMemoized(
      () => HistoryEntry.all(
        feed.items,
        pingWindow: pingWindow,
        now: clock.now(),
        format: HistoryFormat.of(locale),
      ),
      [feed.items, pingWindow, locale],
    );
    final actions = useMemoized(HistoryActions.new);
    // The hosts of the first rows in one batched read: tapping one opens
    // its profile at once.
    useWarmHostIndex(context, userDocumentIds: HistoryActions.hostIds(entries));

    // Back on this tab: calls made since the last visit appear without a
    // pull (RN useFocusEffect). The first build is the initial load; a failed
    // quiet refresh keeps the list as it is.
    final latestFeed = useRef(feed)..value = feed;
    useEffect(() {
      void onTab() {
        final f = latestFeed.value;
        if (home.tab.value != HomeTab.history || f.firstPage.data == null) {
          return;
        }
        unawaited(f.refresh().then((_) {}, onError: (Object _) {}));
      }

      home.tab.addListener(onTab);
      return () => home.tab.removeListener(onTab);
    }, [home]);

    Future<void> refresh() async {
      try {
        await feed.refresh();
        CallUiEvents.historyRefreshed(success: true);
      } on ApiException catch (e) {
        CallUiEvents.historyRefreshed(
          success: false,
          error: Analytics.errorCode(e),
        );
        CToast.error(e);
      }
    }

    final first = feed.firstPage;
    final hasUser = SessionStore.instance.value.userDocumentId != null;
    final busy = first.isLoading || first.isFetching;
    _useHistoryAnalytics(feed, entries, hasUser: hasUser);
    // RN: 120 under the last row inside the bottom safe area, which clears
    // the floating navbar. View padding: fixed while a keyboard is up.
    // Edge to edge: only the room under the last row.
    final padding = EdgeInsets.only(
      bottom: 120.ms + MediaQuery.viewPaddingOf(context).bottom,
    );

    final Widget body;
    if (entries.isEmpty && hasUser && first.data == null && busy) {
      body = const HistorySkeleton();
    } else {
      // RN: a failed page 1 shows a retry, never "No call history found".
      final failed = entries.isEmpty && (first.isError || !hasUser);
      body = InfiniteScroll(
        padding: padding,
        hasMore: feed.hasMore,
        loadingMore: feed.isLoadingMore,
        loadMoreFailed: feed.loadMoreError != null,
        onLoadMore: () {
          if (feed.hasMore && !feed.isLoadingMore) {
            CallUiEvents.historyLoadMore(count: entries.length);
          }
          feed.loadMore();
        },
        onRefresh: refresh,
        onScroll: NavbarCollapse.instance.track,
        endLabel: entries.isEmpty ? null : 'call:history.end',
        loadingBuilder: (_) => const HistorySkeleton.more(),
        slivers: [
          if (failed)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _LoadFailed(
                error: first.error,
                onRetry: () => first.refetch(),
              ),
            )
          else if (entries.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: CStateView.empty(
                title: 'call:history.empty',
                message: null,
              ),
            )
          else
            SliverVariedExtentList.builder(
              itemCount: entries.length,
              itemExtentBuilder: (i, _) => i < entries.length
                  ? HistoryLayout.extent(ping: entries[i].showPing)
                  : null,
              itemBuilder: (_, i) {
                final e = entries[i];
                return HistoryRow(
                  key: ValueKey(e.key),
                  entry: e,
                  onOpen: (e) {
                    CallUiEvents.historyRowTapped(
                      direction: e.direction.name,
                      outcome: e.outcome.name,
                      video: e.isVideo,
                      peerId: e.counterpartId,
                    );
                    actions.openProfile(context, e);
                  },
                  onMenu: (e) => actions.openMenu(context, e),
                );
              },
            ),
        ],
      );
    }

    // The title is the shell's HistoryTopBar, like the other tabs.
    return body;
  }
}

/// Page 1's state (loaded / empty / failed) once per mount and state, and
/// every failed next-page load.
void _useHistoryAnalytics(
  CallHistoryFeed feed,
  List<HistoryEntry> entries, {
  required bool hasUser,
}) {
  final first = feed.firstPage;
  final reported = useRef<String?>(null);
  final hasData = first.data != null;
  final failed = entries.isEmpty && first.isError && !first.isFetching;
  useEffect(() {
    final state = hasData
        ? (entries.isEmpty ? 'empty' : 'loaded')
        : (failed && hasUser ? 'failed' : null);
    if (state == null || reported.value == state) return null;
    reported.value = state;
    switch (state) {
      case 'loaded':
        CallUiEvents.historyLoaded(
          count: entries.length,
          hasMore: feed.hasMore,
        );
      case 'empty':
        CallUiEvents.historyEmpty();
      default:
        CallUiEvents.historyLoadFailed(error: Analytics.errorCode(first.error));
    }
    return null;
  }, [hasData, entries.isEmpty, failed]);
  final moreError = feed.loadMoreError;
  useEffect(() {
    if (moreError != null) {
      CallUiEvents.historyLoadMoreFailed(error: Analytics.errorCode(moreError));
    }
    return null;
  }, [moreError]);
}

/// "Couldn't load call history" with the reason and a retry.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error, required this.onRetry});
  final ApiException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    final offline =
        e?.type == ApiErrorType.network || e?.type == ApiErrorType.timeout;
    return CStateView(
      title: 'call:history.load_failed',
      message: e?.localizedMessage(context),
      translateMessage: false,
      icon: offline ? LucideIcons.wifiOff : LucideIcons.circleAlert,
      actionLabel: 'actions.retry',
      onAction: onRetry,
    );
  }
}
