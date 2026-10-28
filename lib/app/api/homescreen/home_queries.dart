import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_inflight.dart';
import '../../../core/query/query_persist.dart';
import '../listingflow/filter_models.dart';
import '../listingflow/host_index.dart';
import '../listingflow/listing_models.dart';
import 'feed_shuffle.dart';
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
  // Launch: last session's page 1 paints at once, then refreshes.
  final hydrated = useMemoized(_hydrateFeed);
  final query = useApiInfiniteQuery<HostPage>(
    HomeKeys.feed,
    _fetchFeedPage,
    context: context,
    hasMore: (last) => last.hasMore,
    staleDuration: StaleTime.short,
  );
  useEffect(() {
    if (hydrated) {
      WidgetsBinding.instance.addPostFrameCallback((_) => query.refetch());
    }
    return null;
  }, const []);

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
    FeedShuffle.reseed(); // a new order within each page
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
/// On disk like the feed's first page.
QueryResult<List<HostCard>, ApiException> usePopularHosts(
  BuildContext context, {
  bool enabled = true,
}) => usePersistedQuery<List<HostCard>>(
  HomeKeys.popular,
  _fetchPopular,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.short,
  toJson: (hosts) => [for (final h in hosts) h.toJson()],
  fromJson: (json) => [for (final row in json! as List) HostCard.fromJson(row)],
);

/// Startup prefetch: Discover's page 1 and Popular, so Home opens on them.
/// Completes once feed page 1 is in (or failed); at once when it is fresh.
Future<void> prefetchDiscover() {
  final feed = queryCache.entry<FeedData>(HomeKeys.feed);
  final updatedAt = feed?.dataUpdatedAt;
  final feedFresh =
      feed?.data != null &&
      updatedAt != null &&
      !feed!.isInvalidated &&
      DateTime.now().difference(updatedAt) < StaleTime.short;
  var firstPage = Future<void>.value();
  if (!feedFresh) {
    // Same in-flight id as the hook's first page: a mounting grid joins it.
    firstPage =
        QueryInflight.run<HostPage>([
          ...HomeKeys.feed,
          '#page',
        ], () => _fetchFeedPage(1)).then((page) {
          // A grid that joined stores its own page 1 (seeding too doubles it).
          if (queryCache.canSeed<FeedData>(HomeKeys.feed)) {
            queryCache.setQueryData<FeedData, ApiException>(
              HomeKeys.feed,
              (_) => FeedData(pages: [page], pageParams: [1]),
            );
          }
        }, onError: (Object _) {});
  }
  queryCache.prefetchQuery<List<HostCard>>(HomeKeys.popular, () async {
    final hosts = await _fetchPopular();
    QueryPersist.write(HomeKeys.popular, [for (final h in hosts) h.toJson()]);
    return hosts;
  });
  return firstPage;
}

/// Every feed page, its hosts shuffled within it ([FeedShuffle]), fills
/// [HostIndex] (profiles open from it); page 1 is also kept on disk.
Future<HostPage> _fetchFeedPage(int page) async {
  final result = _shuffled(await HomeApi.fetchFeedPage(page));
  HostIndex.seed(result.hosts);
  if (page == 1) QueryPersist.write(HomeKeys.feed, result.toJson());
  return result;
}

Future<List<HostCard>> _fetchPopular() async {
  final hosts = await HomeApi.fetchPopularHosts();
  HostIndex.seed(hosts);
  return hosts;
}

/// Puts last session's page 1 into an empty cache; true when it did (the
/// caller refetches it).
bool _hydrateFeed() {
  if (queryCache.getQueryData<FeedData, ApiException>(HomeKeys.feed) != null) {
    return false;
  }
  final saved = QueryPersist.read<HostPage>(HomeKeys.feed, HostPage.fromJson);
  if (saved == null) return false;
  // In this launch's order, which the refetch keeps: no jump when it lands.
  final page = _shuffled(saved);
  queryCache.setQueryData<FeedData, ApiException>(
    HomeKeys.feed,
    (_) => FeedData(pages: [page], pageParams: [1]),
  );
  return true;
}

HostPage _shuffled(HostPage p) => HostPage(
  page: p.page,
  hosts: FeedShuffle.within(p.hosts),
  hasMore: p.hasMore,
  total: p.total,
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
