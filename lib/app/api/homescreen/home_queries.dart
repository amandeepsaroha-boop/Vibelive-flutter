import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fquery/fquery.dart' show useInfiniteQuery;
import 'package:fquery_core/fquery_core.dart'
    show InfiniteQueryData, InfiniteQueryResult;

import '../../../core/network/api_client.dart';
import '../../../core/query/query_hooks.dart';
import '../listingflow/filter_models.dart';
import '../listingflow/listing_models.dart';
import 'home_api.dart';
import 'home_keys.dart';
import 'home_models.dart';

typedef FeedData = InfiniteQueryData<HostPage, int>;

/// Filtered views keep pulling pages until at least this many hosts match.
const minFilteredResults = 6;

/// After a failed next page, further page loads wait this long: the feed
/// asks on every scroll event near the bottom.
const _failedPageHold = Duration(seconds: 5);

/// The paginated Discover feed ([HomeKeys.feed]).
class DiscoverFeed {
  const DiscoverFeed._({
    required this.query,
    required this.hosts,
    required this.loadMore,
    required this.refresh,
  });

  /// Raw query state (pass to `QueryView`; page 1 errors show its retry).
  final InfiniteQueryResult<HostPage, ApiException, int> query;

  /// Every loaded host, merged by [HostPage.merge].
  final List<HostCard> hosts;

  /// Next page: one at a time, never past the last page, held briefly after
  /// a failure.
  final void Function() loadMore;

  /// Pull-to-refresh: starts over at page 1. Completes when the fetch ends;
  /// a failure keeps the hosts on screen and sets `query.isRefetchError`.
  final Future<void> Function() refresh;

  bool get hasMore => query.hasNextPage;

  /// Hosts the next page brings: a full page, or what's left of the
  /// server's total when that's fewer. Null when nothing is coming.
  int? get incoming {
    final pages = query.data?.pages;
    if (!hasMore || pages == null || pages.isEmpty) return null;
    final total = pages.last.total;
    if (total == null) return HomeApi.pageSize;
    final loaded = pages.fold<int>(0, (n, p) => n + p.hosts.length);
    return (total - loaded).clamp(0, HomeApi.pageSize);
  }

  /// fquery also flags page 1 as a forward fetch, hence the data check.
  bool get isLoadingMore => query.isFetchingNextPage && query.data != null;
}

DiscoverFeed useDiscoverFeed(BuildContext context) {
  final query = useInfiniteQuery<HostPage, ApiException, int>(
    HomeKeys.feed,
    (page) => ApiClient.guard(() => HomeApi.fetchFeedPage(page)),
    context: context,
    initialPageParam: 1,
    getNextPageParam: (last, _, lastPage, _) =>
        last.hasMore ? lastPage + 1 : null,
    staleDuration: StaleTime.short,
  );

  final pages = query.data?.pages;
  final hosts = useMemoized(() => HostPage.merge(pages ?? const []), [pages]);

  final pendingRefresh = useRef<Completer<void>?>(null);
  if (!query.isFetching && pendingRefresh.value != null) {
    pendingRefresh.value!.complete();
    pendingRefresh.value = null;
  }

  void loadMore() {
    if (!query.hasNextPage || query.isFetching) return;
    final failedAt = query.isError ? query.errorUpdatedAt : null;
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _failedPageHold) {
      return;
    }
    query.fetchNextPage();
  }

  Future<void> refresh() {
    final done = pendingRefresh.value ??= Completer<void>();
    final data = queryCache.getQueryData<FeedData, ApiException>(HomeKeys.feed);
    if (!query.isFetching && data != null && data.pages.length > 1) {
      // Not an optimistic update: trims the cache to page 1 so the refetch
      // below reloads one page (as RN did) instead of every loaded page.
      queryCache.setQueryData<FeedData, ApiException>(
        HomeKeys.feed,
        (_) => FeedData(
          pages: [data.pages.first],
          pageParams: [data.pageParams.first],
        ),
      );
    }
    query.refetch();
    return done.future;
  }

  return DiscoverFeed._(
    query: query,
    hosts: hosts,
    loadMore: loadMore,
    refresh: refresh,
  );
}

/// Popular tab. Its own query, so a failure never blanks the main feed.
QueryResult<List<HostCard>, ApiException> usePopularHosts(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<List<HostCard>>(
  HomeKeys.popular,
  HomeApi.fetchPopularHosts,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.short,
);

/// What the grid shows for [tab] + [filter]. Filtering is client-side over
/// a paginated feed, so while fewer than [minFilteredResults] loaded hosts
/// match, the next page is pulled (the scroll trigger never fires on a short
/// list). Popular is its own list: paging the feed cannot add to it.
List<HostCard> useDiscoverHosts({
  required DiscoverFeed feed,
  List<HostCard>? popular,
  DiscoverTab tab = DiscoverTab.all,
  HostFilter filter = HostFilter.none,
  List<SupportTopic> topics = const [],
}) {
  final source = tab.isPopular ? (popular ?? const <HostCard>[]) : feed.hosts;
  final visible = useMemoized(
    () => [
      for (final h in source)
        if (tab.matches(h, topics) && filter.matches(h)) h,
    ],
    [source, tab, filter, topics],
  );

  final wantsMore =
      !tab.isPopular &&
      (tab.isTopic || filter.isActive) &&
      visible.length < minFilteredResults &&
      feed.hasMore &&
      !feed.query.isFetching;
  useEffect(() {
    if (!wantsMore) return null;
    // Not during build: fetching notifies listeners synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) => feed.loadMore());
    return null;
  }, [wantsMore, visible.length, feed.hosts.length]);

  return visible;
}
