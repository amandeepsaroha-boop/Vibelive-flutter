import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_exception.dart';

import '../../../core/utils/scale.dart';
import '../../api/authscreen/interests_models.dart';
import '../../api/authscreen/interests_queries.dart';
import '../../api/homescreen/home_models.dart';
import '../../api/homescreen/home_queries.dart';
import '../../api/listingflow/filter_models.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../component/c_button.dart';
import '../../component/c_state_view.dart';
import '../../component/infinite_scroll.dart';
import '../../component/skeleton.dart';
import '../../listingflow/profile/host_profile_sheet.dart';
import '../../listingflow/widgets/host_grid_card.dart';
import '../../navbar/bottombar/navbar_collapse.dart';
import '../helper/discover_layout.dart';
import '../helper/home_controller.dart';
import 'active_filters.dart';
import 'topic_tabs.dart';

/// The Discover tab (RN `VibeScreen`): topic strip, active filters, and the
/// paged host grid with skeleton, pull-to-refresh and infinite loading.
class DiscoverView extends HookWidget {
  const DiscoverView({super.key, required this.home, this.initialTopic});

  final HomeController home;

  /// `?topic=` pins a topic tab right after Popular.
  final String? initialTopic;

  @override
  Widget build(BuildContext context) {
    final pinned = useMemoized(() => DiscoverTab.fromParam(initialTopic), [
      initialTopic,
    ]);
    final tab = useState(pinned ?? DiscoverTab.all);
    final feed = useDiscoverFeed(context);
    // Loaded with the feed (RN), so the first tap on Popular is instant.
    final popular = usePopularHosts(context);
    final form = useInterestForm(context);
    final filter = useValueListenable(home.filter);
    final scroll = useScrollController();

    final formTopics = useMemoized(() => _topicsOf(form.data), [form.data]);
    final topics = useMemoized(
      () => formTopics.isNotEmpty || form.isLoading
          ? formTopics
          : SupportTopic.fromHosts(feed.hosts),
      [formTopics, form.isLoading, feed.hosts],
    );
    final tabs = useMemoized(() {
      final out = <DiscoverTab>[DiscoverTab.all, DiscoverTab.popular];
      void add(DiscoverTab? t) {
        if (t != null &&
            !out.any((x) => sameText(x.label, t.label) && x.kind == t.kind)) {
          out.add(t);
        }
      }

      add(pinned);
      for (final t in topics) {
        add(DiscoverTab.topic(t.label));
      }
      add(tab.value); // the selected chip never disappears
      return out;
    }, [topics, tab.value, pinned]);

    final hosts = useDiscoverHosts(
      feed: feed,
      popular: popular.data,
      tab: tab.value,
      filter: filter,
      topics: topics,
    );
    final plain = tab.value.isAll && !filter.isActive;
    // Rows already on screen stay the same objects when a page lands, and
    // so do their widgets (below): only new or changed rows build.
    final lastRows = useRef(const <DiscoverRow>[]);
    final plan = useMemoized(
      () => DiscoverLayout.plan(
        hosts,
        holdLeftoverFeatured: feed.hasMore && plain,
        previous: lastRows.value,
      ),
      [hosts, feed.hasMore, plain],
    );
    final rows = lastRows.value = plan.rows;
    // Row widgets are reused as-is; their sizes are scaled to the window.
    final rowWidgets = useMemoized(Expando<Widget>.new, [
      MediaQuery.sizeOf(context),
    ]);
    final rowIndex = useMemoized(
      () => {for (final (i, r) in rows.indexed) r.key: i},
      [rows],
    );

    // Discover tapped again: scroll to the top, or refresh when already there.
    final latestFeed = useRef(feed)..value = feed;
    useEffect(() {
      void onReselect() {
        if (!scroll.hasClients) return;
        if (scroll.offset <= 10) {
          latestFeed.value.refresh();
        } else {
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }

      home.discoverReselect.addListener(onReselect);
      return () => home.discoverReselect.removeListener(onReselect);
    }, [home]);

    void selectTab(DiscoverTab next) {
      if (TopicTabs.same(next, tab.value)) return;
      tab.value = next;
      if (scroll.hasClients) scroll.jumpTo(0);
    }

    // A `?topic=` link while Home is open selects that topic (RN).
    useEffect(() {
      final next = pinned;
      if (next != null && !TopicTabs.same(next, tab.value)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) selectTab(next);
        });
      }
      return null;
    }, [pinned]);

    final isPopular = tab.value.isPopular;
    // The next page's shape, as skeleton. Only on the plain feed: a
    // filtered view can't tell how many of the next cards will match.
    final next = plain && !isPopular && feed.isLoadingMore
        ? plan.next(feed.incoming ?? 0)
        : null;
    final loading =
        hosts.isEmpty &&
        (isPopular
            ? popular.isLoading
            : (feed.query.data == null || (feed.query.isFetching && !plain))) &&
        !(isPopular
            ? popular.isError
            : feed.query.isError && feed.query.data == null);
    final error = isPopular
        ? (popular.isError && popular.data == null ? popular.error : null)
        : (feed.query.isError && feed.query.data == null
              ? feed.query.error
              : null);
    // Pull-to-refresh also reloads the wallet balance in the header (RN).
    Future<void> refresh() async {
      invalidateWalletQueries();
      isPopular ? await popular.refetch() : await feed.refresh();
    }

    // RN: 140 above the bottom safe area, clear of the floating navbar.
    final padding = EdgeInsets.fromLTRB(
      10.ms,
      10.ms,
      10.ms,
      140.ms + MediaQuery.viewPaddingOf(context).bottom,
    );
    return Column(
      children: [
        TopicTabs(
          tabs: tabs,
          selected: tab.value,
          loading: form.isLoading && formTopics.isEmpty,
          onSelect: selectTab,
        ),
        if (filter.isActive)
          ActiveFilters(
            filter: filter,
            onChanged: (f) => home.filter.value = f,
          ),
        Expanded(
          child: loading
              ? Padding(
                  padding: padding.copyWith(bottom: 0),
                  child: const _FeedSkeleton(),
                )
              : InfiniteScroll(
                  controller: scroll,
                  padding: padding,
                  hasMore: !isPopular && feed.hasMore,
                  loadingMore: feed.isLoadingMore,
                  loadMoreFailed: feed.query.isFetchNextPageError,
                  onLoadMore: feed.loadMore,
                  onRefresh: refresh,
                  endLabel: rows.isEmpty ? null : 'home:feed.end',
                  onScroll: NavbarCollapse.instance.track,
                  // Filtered view: the count is unknown, so one plain pair
                  // row (never a spinner in a list).
                  loadingBuilder: next == null
                      ? (_) => const Shimmer(child: _SkeletonRow())
                      : (_) => _MoreSkeleton(next),
                  slivers: [
                    if (error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _LoadError(error: error, onRetry: refresh),
                      )
                    else if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: CStateView.empty(
                          title: tab.value.emptyKey,
                          message: null,
                        ),
                      )
                    else
                      SliverVariedExtentList.builder(
                        itemCount: rows.length,
                        itemExtentBuilder: (i, _) =>
                            i < rows.length ? rows[i].height + 12.ms : null,
                        findChildIndexCallback: (key) => key is ValueKey<String>
                            ? rowIndex[key.value]
                            : null,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          // The half row the next card lands in: its empty
                          // slot shows that card's skeleton meanwhile.
                          if ((next?.fillsSlot ?? false) &&
                              i == rows.length - 1) {
                            return _Row(
                              row,
                              key: ValueKey(row.key),
                              pendingSlot: true,
                            );
                          }
                          return rowWidgets[row] ??= _Row(
                            row,
                            key: ValueKey(row.key),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static List<SupportTopic> _topicsOf(InterestForm? form) => [
    for (final o
        in form?.question(SupportTopicKey.question)?.options ??
            const <InterestOption>[])
      if (!o.isDeprecated && o.value.isNotEmpty)
        SupportTopic(
          label: o.label.isEmpty ? o.value : o.label,
          value: o.value,
        ),
  ];
}

class _Row extends StatelessWidget {
  const _Row(this.row, {super.key, this.pendingSlot = false});
  final DiscoverRow row;

  /// A half row whose second card is loading: a skeleton in its place.
  final bool pendingSlot;

  @override
  Widget build(BuildContext context) {
    void open(HostCard h) => showHostProfile(context, h);
    final gap = SizedBox(width: 12.ms);
    return Padding(
      padding: EdgeInsets.only(bottom: 12.ms),
      child: row.featured
          ? HostGridCard(host: row.hosts.first, featured: true, onTap: open)
          : Row(
              children: [
                Expanded(
                  child: HostGridCard(host: row.hosts.first, onTap: open),
                ),
                gap,
                Expanded(
                  child: row.hosts.length > 1
                      ? HostGridCard(host: row.hosts[1], onTap: open)
                      : pendingSlot
                      ? const Shimmer(child: HostGridCardSkeleton())
                      : const SizedBox.shrink(),
                ),
              ],
            ),
    );
  }
}

/// RN copy: "Couldn't load hosts. Check your connection." + TRY AGAIN.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});
  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline =
        error.type == ApiErrorType.network ||
        error.type == ApiErrorType.timeout;
    return CStateView(
      title: 'home:feed.load_error',
      icon: offline ? LucideIcons.wifiOff : LucideIcons.circleAlert,
      actionLabel: 'home:feed.try_again',
      actionVariant: CButtonVariant.primary,
      onAction: onRetry,
    );
  }
}

/// A skeleton feed row, built like [_Row]: the same height, 12 gap under
/// it, and the same card widths (a lone regular card keeps half the row).
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({this.featured = false, this.cards = 2});

  final bool featured;

  /// Regular rows: 1 or 2 cards.
  final int cards;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12.ms),
    child: SizedBox(
      height: DiscoverRow.heightOf(featured: featured),
      child: featured
          ? const HostGridCardSkeleton(featured: true)
          : Row(
              children: [
                const Expanded(child: HostGridCardSkeleton()),
                SizedBox(width: 12.ms),
                Expanded(
                  child: cards > 1
                      ? const HostGridCardSkeleton()
                      : const SizedBox.shrink(),
                ),
              ],
            ),
    ),
  );
}

/// First-load skeleton: the feed's own pattern (a featured card, then
/// pairs), as many rows as fill the viewport.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final gap = 12.ms;
      final rows = <Widget>[const _SkeletonRow(featured: true)];
      var filled = DiscoverRow.heightOf(featured: true) + gap;
      while (filled < box.maxHeight) {
        rows.add(const _SkeletonRow());
        filled += DiscoverRow.heightOf(featured: false) + gap;
      }
      return ClipRect(
        child: Shimmer(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      );
    },
  );
}

/// Load-more footer: the next row's shape, as a skeleton (nothing when the
/// next card only fills the last row's empty slot).
class _MoreSkeleton extends StatelessWidget {
  const _MoreSkeleton(this.next);
  final DiscoverNext next;

  @override
  Widget build(BuildContext context) => next.cards == 0
      ? const SizedBox.shrink()
      : Shimmer(
          child: _SkeletonRow(featured: next.featured, cards: next.cards),
        );
}
