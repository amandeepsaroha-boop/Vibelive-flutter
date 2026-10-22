import 'dart:async';

import 'package:fquery_core/fquery_core.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'query_inflight.dart';

/// App-wide query cache (TanStack Query equivalent via fquery).
/// Provided to the widget tree by `CacheProvider` in `main.dart`; non-widget
/// code uses this instance directly.
///
/// Stale-while-revalidate everywhere: cached data always renders at once and
/// a mount only refetches once it is older than its stale time.
///
/// `retryCount` is 0 on purpose: [ApiClient] already retries transient GET
/// failures, and fquery would also retry 4xx responses.
final QueryCache queryCache = QueryCache(
  defaultQueryOptions: DefaultQueryOptions(
    staleDuration: StaleTime.short,
    cacheDuration: const Duration(minutes: 5),
    refetchOnMount: RefetchOnMount.stale,
    retryCount: 0,
  ),
);

/// Common stale times. Pick per query instead of inventing numbers.
abstract final class StaleTime {
  static const none = Duration.zero;

  /// Feeds, lists, my profile, wallet, history (writes invalidate them).
  static const short = Duration(minutes: 1);
  static const medium = Duration(minutes: 5);
  static const long = Duration(minutes: 30);

  /// Reference data that almost never changes (countries, languages…).
  static const static = Duration(hours: 12);
}

extension QueryCacheX on QueryCache {
  /// Imperative fetch for non-widget code (services, push handlers, startup
  /// prefetch). Returns cached data when still fresh, else fetches and stores
  /// it under [key] so hooks on the same key render it instantly. Joins a
  /// request already running for [key] (a hook's or another caller's)
  /// unless [staleDuration] is [StaleTime.none] (forced refresh).
  ///
  /// Use the same `T` as the hook for that key — fquery's cache is typed.
  Future<T> fetchQuery<T>(
    RawQueryKey key,
    Future<T> Function() fetcher, {
    Duration staleDuration = StaleTime.short,
  }) async {
    final cached = freshData<T>(key, staleDuration);
    if (cached != null) return cached;
    final data = await QueryInflight.run<T>(
      key,
      () => ApiClient.guard(fetcher),
      fresh: staleDuration == StaleTime.none,
    );
    setQueryData<T, ApiException>(key, (_) => data);
    return data;
  }

  /// Data under [key] younger than [maxAge] (and not invalidated), else null.
  T? freshData<T>(RawQueryKey key, Duration maxAge) {
    if (maxAge == Duration.zero) return null;
    final query = entry<T>(key);
    final updatedAt = query?.dataUpdatedAt;
    final data = query?.data;
    if (data != null &&
        updatedAt != null &&
        !query!.isInvalidated &&
        DateTime.now().difference(updatedAt) < maxAge) {
      return data;
    }
    return null;
  }

  /// The cache entry under [key] (data, timestamps, flags), or null.
  Query<T, ApiException>? entry<T>(RawQueryKey key) {
    try {
      return get<T, ApiException>(QueryKey<T, ApiException>(key));
    } on QueryNotFoundException {
      return null;
    }
  }

  /// Fire-and-forget [fetchQuery] (e.g. warm a screen before navigating).
  void prefetchQuery<T>(
    RawQueryKey key,
    Future<T> Function() fetcher, {
    Duration staleDuration = StaleTime.short,
  }) {
    unawaited(
      fetchQuery<T>(
        key,
        fetcher,
        staleDuration: staleDuration,
      ).then((_) {}, onError: (Object _) {}),
    );
  }

  /// Marks every query under [keys] stale; mounted ones refetch. Requests
  /// still running for them were sent before the change: never joined.
  void invalidateAll(Iterable<RawQueryKey> keys) {
    QueryInflight.forget(keys);
    for (final key in keys) {
      invalidateQueries(key);
    }
  }

  /// Drops everything (logout).
  void clear() {
    QueryInflight.clear();
    removeQueries(const []);
  }
}
