import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fquery/fquery.dart';
import 'package:fquery_core/fquery_core.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'query_client.dart';
import 'query_observe.dart';
import 'query_persist.dart';

export 'package:fquery_core/fquery_core.dart'
    show
        InfiniteQueryData,
        InfiniteQueryResult,
        QueryResult,
        MutationResult,
        RawQueryKey,
        RefetchOnMount;

export '../network/api_exception.dart';
export 'query_client.dart' show StaleTime, queryCache, QueryCacheX;

/// `useQuery` with the app conventions: error type is always
/// [ApiException] and the fetcher is guarded so nothing else can escape.
/// Cached data renders at once; one request per key at a time (shared with
/// `queryCache.fetchQuery`); the widget rebuilds only for its own key.
///
/// ```dart
/// QueryResult<AppConfig, ApiException> useAppConfig(BuildContext context) =>
///     useApiQuery(SplashKeys.appConfig, SplashApi.fetchAppConfig,
///         context: context, staleDuration: StaleTime.long);
/// ```
QueryResult<T, ApiException> useApiQuery<T>(
  RawQueryKey key,
  Future<T> Function() fetcher, {
  required BuildContext context,
  bool enabled = true,
  Duration? staleDuration,
  Duration? cacheDuration,
  Duration? refetchInterval,
  RefetchOnMount? refetchOnMount,
}) {
  return useCacheQuery<T>(
    key,
    () => ApiClient.guard(fetcher),
    context: context,
    enabled: enabled,
    staleDuration: staleDuration,
    cacheDuration: cacheDuration,
    refetchInterval: refetchInterval,
    refetchOnMount: refetchOnMount,
  );
}

/// Paged list ([initialPage], [initialPage] + 1, …) with the conventions of
/// [useApiQuery]. [hasMore] tells whether a page has a next one.
InfiniteQueryResult<P, ApiException, int> useApiInfiniteQuery<P>(
  RawQueryKey key,
  Future<P> Function(int page) fetchPage, {
  required BuildContext context,
  required bool Function(P lastPage) hasMore,
  int initialPage = 1,
  bool enabled = true,
  Duration? staleDuration,
}) => useCacheInfiniteQuery<P>(
  key,
  (page) => ApiClient.guard(() => fetchPage(page)),
  context: context,
  initialPage: initialPage,
  hasMore: hasMore,
  enabled: enabled,
  staleDuration: staleDuration,
);

/// [useApiQuery] plus a disk copy: the last saved result is returned while
/// the first network fetch is in flight (or failing), so the screen never
/// starts empty. [toJson]/[fromJson] must round-trip `T`.
QueryResult<T, ApiException> usePersistedQuery<T>(
  RawQueryKey key,
  Future<T> Function() fetcher, {
  required BuildContext context,
  required Object? Function(T data) toJson,
  required T Function(Object? json) fromJson,
  bool enabled = true,
  Duration? staleDuration,
  Duration? cacheDuration,
}) {
  final result = useApiQuery<T>(
    key,
    () async {
      final data = await fetcher();
      QueryPersist.write(key, toJson(data));
      return data;
    },
    context: context,
    enabled: enabled,
    staleDuration: staleDuration,
    cacheDuration: cacheDuration,
  );

  final keyId = key.toString();
  final disk = useMemoized(
    () => result.data == null ? QueryPersist.read<T>(key, fromJson) : null,
    [keyId],
  );

  if (result.data != null || disk == null) return result;
  return QueryResult<T, ApiException>(
    data: disk,
    dataUpdatedAt: null,
    error: result.error,
    errorUpdatedAt: result.errorUpdatedAt,
    isError: result.isError,
    isLoading: false,
    isFetching: result.isFetching || result.isLoading,
    isSuccess: true,
    status: QueryStatus.success,
    refetch: result.refetch,
    isInvalidated: result.isInvalidated,
    isRefetchError: result.isError,
  );
}

/// `useMutation` with the app conventions. Keys in [invalidates] are marked
/// stale after success, so every screen showing them refetches.
///
/// ```dart
/// final block = useApiMutation<void, String>(
///   ClientApi.blockUser,
///   invalidates: [ClientKeys.blockedUsers],
/// );
/// block.mutate(userId);
/// ```
MutationResult<T, ApiException, V> useApiMutation<T, V>(
  Future<T> Function(V variables) mutationFn, {
  List<RawQueryKey> invalidates = const [],
  void Function(T data, V variables)? onSuccess,
  void Function(ApiException error, V variables)? onError,
  void Function()? onSettled,
}) {
  return useMutation<T, ApiException, V, void>(
    (v) => ApiClient.guard(() => mutationFn(v)),
    onSuccess: (data, v, _) {
      queryCache.invalidateAll(invalidates);
      onSuccess?.call(data, v);
    },
    onError: (error, v, _) => onError?.call(error, v),
    onSettled: (_, _, _, _) => onSettled?.call(),
  );
}
