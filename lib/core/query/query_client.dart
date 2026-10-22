import 'dart:async';

import 'package:fquery_core/fquery_core.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';

/// App-wide query cache (TanStack Query equivalent via fquery).
/// Provided to the widget tree by `CacheProvider` in `main.dart`; non-widget
/// code uses this instance directly.
///
/// `retryCount` is 0 on purpose: [ApiClient] already retries transient GET
/// failures, and fquery would also retry 4xx responses.
final QueryCache queryCache = QueryCache(
  defaultQueryOptions: DefaultQueryOptions(
    staleDuration: const Duration(seconds: 30),
    cacheDuration: const Duration(minutes: 5),
    refetchOnMount: RefetchOnMount.stale,
    retryCount: 0,
  ),
);

/// Common stale times. Pick per query instead of inventing numbers.
abstract final class StaleTime {
  static const none = Duration.zero;
  static const short = Duration(seconds: 30);
  static const medium = Duration(minutes: 5);
  static const long = Duration(minutes: 30);

  /// Reference data that almost never changes (countries, languages…).
  static const static = Duration(hours: 12);
}

extension QueryCacheX on QueryCache {
  /// Imperative fetch for non-widget code (services, push handlers, startup
  /// prefetch). Returns cached data when still fresh, else fetches and stores
  /// it under [key] so hooks on the same key render it instantly.
  ///
  /// Use the same `T` as the hook for that key — fquery's cache is typed.
  Future<T> fetchQuery<T>(
    RawQueryKey key,
    Future<T> Function() fetcher, {
    Duration staleDuration = StaleTime.short,
  }) async {
    try {
      final query = get<T, ApiException>(QueryKey<T, ApiException>(key));
      final updatedAt = query.dataUpdatedAt;
      final data = query.data;
      if (data != null &&
          updatedAt != null &&
          !query.isInvalidated &&
          DateTime.now().difference(updatedAt) < staleDuration) {
        return data;
      }
    } on QueryNotFoundException {
      // first fetch
    }
    final data = await ApiClient.guard(fetcher);
    setQueryData<T, ApiException>(key, (_) => data);
    return data;
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

  /// Marks every query under [keys] stale; mounted ones refetch.
  void invalidateAll(Iterable<RawQueryKey> keys) {
    for (final key in keys) {
      invalidateQueries(key);
    }
  }

  /// Drops everything (logout).
  void clear() => removeQueries(const []);
}
