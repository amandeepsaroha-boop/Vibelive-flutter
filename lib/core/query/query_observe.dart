import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fquery/fquery.dart' show CacheProvider;
import 'package:fquery_core/fquery_core.dart';

import '../network/api_exception.dart';
import 'query_inflight.dart';

/// fquery's `useQuery` / `useInfiniteQuery`, with one difference: a widget
/// rebuilds only when ITS query changes. fquery's hooks rebuild on every
/// cache event of every query (each fetch start / end anywhere in the app
/// rebuilt every screen holding a query).
///
/// Behaviour is otherwise the same: refetch on mount when stale, refetch
/// when invalidated, a new observer when the key changes or the query is
/// removed (logout).

/// Single-value query; see `useApiQuery`.
QueryResult<T, ApiException> useCacheQuery<T>(
  RawQueryKey key,
  Future<T> Function() fetcher, {
  required BuildContext context,
  required bool enabled,
  Duration? staleDuration,
  Duration? cacheDuration,
  Duration? refetchInterval,
  RefetchOnMount? refetchOnMount,
}) {
  final cache = CacheProvider.get(context);
  final id = QueryInflight.id(key);
  final fetcherRef = useRef(fetcher)..value = fetcher;
  final generation = useState(0);

  final observer = useMemoized(
    () => QueryObserver<T, ApiException>(
      cache: cache,
      queryKey: QueryKey<T, ApiException>(key),
      queryFn: () => QueryInflight.run<T>(key, () => fetcherRef.value()),
      enabled: enabled,
      staleDuration: staleDuration,
      cacheDuration: cacheDuration,
      refetchInterval: refetchInterval,
      refetchOnMount: refetchOnMount,
    ),
    [id, cache, generation.value],
  );
  _useOwnQuery(
    cache,
    observer,
    generation,
    () => cache.build<T, ApiException>(
      queryKey: observer.queryKey,
      observer: observer,
    ),
  );

  useEffect(
    () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        observer.updateOptions(
          QueryOptions<T, ApiException>(
            queryKey: observer.queryKey,
            queryFn: () => QueryInflight.run<T>(key, () => fetcherRef.value()),
            enabled: enabled,
            staleDuration: staleDuration,
            cacheDuration: cacheDuration,
            refetchInterval: refetchInterval,
            refetchOnMount: refetchOnMount,
          ),
        );
      });
      return null;
    },
    [
      observer,
      enabled,
      staleDuration,
      cacheDuration,
      refetchInterval,
      refetchOnMount,
    ],
  );

  final q = observer.query;
  return QueryResult<T, ApiException>(
    data: q.data,
    dataUpdatedAt: q.dataUpdatedAt,
    error: q.error,
    errorUpdatedAt: q.errorUpdatedAt,
    isError: q.isError,
    isLoading: q.isLoading,
    isFetching: q.isFetching,
    isSuccess: q.isSuccess,
    status: q.status,
    refetch: observer.fetch,
    isInvalidated: q.isInvalidated,
    isRefetchError: q.isRefetchError,
  );
}

/// Paged query with integer page params; see `useApiInfiniteQuery`.
InfiniteQueryResult<P, ApiException, int> useCacheInfiniteQuery<P>(
  RawQueryKey key,
  Future<P> Function(int page) fetchPage, {
  required BuildContext context,
  required int initialPage,
  required bool Function(P lastPage) hasMore,
  required bool enabled,
  Duration? staleDuration,
}) {
  final cache = CacheProvider.get(context);
  final id = QueryInflight.id(key);
  final fetchRef = useRef(fetchPage)..value = fetchPage;
  final hasMoreRef = useRef(hasMore)..value = hasMore;
  final generation = useState(0);

  // The first page joins a prefetch of it; later pages always load.
  Future<P> load(int page) => page == initialPage
      ? QueryInflight.run<P>([...key, '#page'], () => fetchRef.value(page))
      : fetchRef.value(page);
  int? next(P last, List<P> _, int lastPage, List<int> _) =>
      hasMoreRef.value(last) ? lastPage + 1 : null;

  final observer = useMemoized(
    () => InfiniteQueryObserver<P, ApiException, int>(
      cache: cache,
      queryKey: QueryKey<InfiniteQueryData<P, int>, ApiException>(key),
      queryFn: load,
      enabled: enabled,
      staleDuration: staleDuration,
      initialPageParam: initialPage,
      getNextPageParam: next,
    ),
    [id, cache, generation.value],
  );
  _useOwnQuery(
    cache,
    observer,
    generation,
    () => cache.build<InfiniteQueryData<P, int>, ApiException>(
      queryKey: observer.queryKey,
      observer: observer,
    ),
  );

  useEffect(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      observer.updateOptions(
        InfiniteQueryOptions<P, ApiException, int>(
          queryKey: observer.queryKey,
          queryFn: load,
          enabled: enabled,
          staleDuration: staleDuration,
          initialPageParam: initialPage,
          getNextPageParam: next,
        ),
      );
    });
    return null;
  }, [observer, enabled, staleDuration]);

  final q = observer.query;
  final data = q.data;
  final forward = q.fetchMeta?.direction == FetchDirection.forward;
  final nextPage = data == null || data.pages.isEmpty
      ? null
      : next(data.pages.last, data.pages, data.pageParams.last, const []);
  final fetchingNext = q.isFetching && forward;
  return InfiniteQueryResult<P, ApiException, int>(
    data: data,
    dataUpdatedAt: q.dataUpdatedAt,
    error: q.error,
    errorUpdatedAt: q.errorUpdatedAt,
    isError: q.isError,
    isLoading: q.isLoading,
    isFetching: q.isFetching,
    isSuccess: q.isSuccess,
    status: q.status,
    refetch: observer.refetch,
    isInvalidated: q.isInvalidated,
    isRefetchError: q.isRefetchError,
    isFetchingNextPage: fetchingNext,
    isFetchingPreviousPage: false,
    fetchNextPage: observer.fetchNextPage,
    fetchPreviousPage: observer.fetchPreviousPage,
    hasNextPage: nextPage != null,
    hasPreviousPage: false,
    isRefetching: q.isFetching && !fetchingNext,
    isFetchNextPageError: q.isError && forward,
    isFetchPreviousPageError: false,
  );
}

/// Mounted observers per key (see [_keepAlive]).
final _live = <QueryKey, Map<Object, void Function()>>{};

/// Starts [observer] after the first frame, disposes it with the widget and
/// rebuilds only when its own cache entry is replaced. A removed entry
/// (logout) bumps [generation] for a fresh observer. [register] re-attaches
/// the observer to its cache entry.
void _useOwnQuery(
  QueryCache cache,
  Observer<dynamic, ApiException, dynamic> observer,
  ValueNotifier<int> generation,
  void Function() register,
) {
  final tick = useState(0);
  useEffect(() {
    var alive = true;
    final key = observer.queryKey;
    var last = cache.queries[key];
    final listenerId = identityHashCode(tick);

    void apply() {
      if (!alive) return;
      final now = cache.queries[key];
      if (identical(now, last)) return;
      last = now;
      if (now == null) {
        generation.value++;
      } else {
        tick.value++;
      }
    }

    void listener() {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        // During build: defer to the next frame.
        SchedulerBinding.instance.addPostFrameCallback((_) => apply());
      } else {
        apply();
      }
    }

    (_live[key] ??= {})[observer] = register;
    observer.subscribe(listenerId, listener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (alive) observer.initialize();
    });
    return () {
      alive = false;
      observer.unsubscribe(listenerId);
      observer.dispose();
      _keepAlive(key, observer);
    };
  }, [observer]);
}

/// fquery schedules garbage collection when ANY observer of a key goes away,
/// even while others still show it: 5 minutes later the entry vanished
/// under a mounted screen, which fell back to a loading state. Re-attaching
/// a remaining observer cancels that timer.
void _keepAlive(QueryKey key, Object disposed) {
  final others = _live[key];
  if (others == null) return;
  others.remove(disposed);
  if (others.isEmpty) {
    _live.remove(key);
  } else {
    others.values.first();
  }
}
