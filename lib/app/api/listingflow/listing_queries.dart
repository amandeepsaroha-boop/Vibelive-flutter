import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fquery_core/fquery_core.dart' show QueryStatus;

import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'listing_api.dart';
import 'listing_keys.dart';
import 'listing_models.dart';
import 'search_api.dart';
import 'search_models.dart';

QueryResult<List<HostCard>, ApiException> useHosts(
  BuildContext context, {
  Map<String, dynamic> query = const {},
  bool enabled = true,
}) => useApiQuery<List<HostCard>>(
  ListingKeys.hosts(query),
  () => ListingApi.fetchHosts(query: query),
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.short,
);

/// Full profile of a search hit (needs [expertDocumentId] or
/// [userDocumentId]; [handler] is the last fallback).
QueryResult<HostCard, ApiException> useHostDetail(
  BuildContext context, {
  String? expertDocumentId,
  String? userDocumentId,
  String? handler,
  bool enabled = true,
}) {
  final expertId = expertDocumentId?.trim() ?? '';
  final userId = userDocumentId?.trim() ?? '';
  return useApiQuery<HostCard>(
    ListingKeys.host(
      expertDocumentId: expertId,
      userDocumentId: userId,
      handler: handler,
    ),
    () => ListingApi.findHost(
      expertDocumentId: expertId,
      userDocumentId: userId,
      handler: handler,
    ),
    context: context,
    enabled: enabled && (expertId.isNotEmpty || userId.isNotEmpty),
    staleDuration: StaleTime.short,
  );
}

/// Profile behind a shared link / `openUserId`. Any host opens; the
/// viewer's own (even pending approval) through the owner lookup.
QueryResult<HostCard, ApiException> useHostByLink(
  BuildContext context,
  String? targetId, {
  bool enabled = true,
}) {
  final target = targetId?.trim() ?? '';
  final own = _isOwnTarget(target);
  return useApiQuery<HostCard>(
    ListingKeys.hostByLink(target, own),
    () => ListingApi.findHostByLink(target, ownUserDocumentId: _ownDoc(own)),
    context: context,
    enabled: enabled && target.isNotEmpty,
    staleDuration: StaleTime.short,
  );
}

/// `GET /search` for [query] (debounce in the UI), with the verification
/// badges merged in once their batched read lands. While a new query loads,
/// the previous results stay on screen; a failed badge read is ignored
/// (badges are decoration and must never blank the results).
QueryResult<SearchResults, ApiException> useSearch(
  BuildContext context,
  String query, {
  int limit = SearchApi.defaultLimit,
}) {
  final q = query.trim();
  final result = useApiQuery<SearchResults>(
    ListingKeys.searchQuery(q, limit),
    () => SearchApi.search(q, limit: limit),
    context: context,
    enabled: q.isNotEmpty,
    staleDuration: StaleTime.short,
  );

  final ids = result.data?.expertDocumentIds ?? const <String>[];
  final badges = useApiQuery<Map<String, HostBadges>>(
    ListingKeys.searchBadges(ids),
    () => SearchApi.fetchBadges(ids),
    context: context,
    enabled: ids.isNotEmpty,
    staleDuration: StaleTime.short,
  );

  final previous = useRef<SearchResults?>(null);
  if (q.isEmpty) previous.value = null;
  final fresh = result.data;
  final badgeData = badges.data;
  final merged = useMemoized(() => fresh?.withBadges(badgeData ?? const {}), [
    fresh,
    badgeData,
  ]);
  if (merged != null) previous.value = merged;

  if (merged != null) {
    return identical(merged, fresh) ? result : _withData(result, merged);
  }
  final kept = previous.value;
  if (kept != null && result.isLoading && q.isNotEmpty) {
    return _withData(result, kept, loading: true);
  }
  return result;
}

/// Outside widgets (opening a search hit on tap).
Future<HostCard> ensureHostDetail({
  String? expertDocumentId,
  String? userDocumentId,
  String? handler,
}) {
  final expertId = expertDocumentId?.trim() ?? '';
  final userId = userDocumentId?.trim() ?? '';
  return queryCache.fetchQuery<HostCard>(
    ListingKeys.host(
      expertDocumentId: expertId,
      userDocumentId: userId,
      handler: handler,
    ),
    () => ListingApi.findHost(
      expertDocumentId: expertId,
      userDocumentId: userId,
      handler: handler,
    ),
  );
}

/// Outside widgets (deep links, post-login actions).
Future<HostCard> ensureHostByLink(String targetId) {
  final target = targetId.trim();
  final own = _isOwnTarget(target);
  return queryCache.fetchQuery<HostCard>(
    ListingKeys.hostByLink(target, own),
    () => ListingApi.findHostByLink(target, ownUserDocumentId: _ownDoc(own)),
  );
}

/// Outside widgets: the profile of a call-log counterpart or a nudging
/// host, by user documentId → expert-profile documentId → numeric user id
/// ([ListingApi.findProfile]). The viewer's own opens via the owner lookup.
Future<HostCard> ensureProfile({
  String? userDocumentId,
  String? userId,
  String? expertDocumentId,
}) {
  final own =
      _isOwnTarget(userDocumentId?.trim() ?? '') ||
      _isOwnTarget(userId?.trim() ?? '');
  return queryCache.fetchQuery<HostCard>(
    ListingKeys.profile(
      userDocumentId: userDocumentId,
      userId: userId,
      expertDocumentId: expertDocumentId,
      own: own,
    ),
    () => ListingApi.findProfile(
      userDocumentId: userDocumentId,
      userId: userId,
      expertDocumentId: expertDocumentId,
      ownUserDocumentId: _ownDoc(own),
    ),
  );
}

/// Outside widgets (the `PING_CLIENT` push handler). Callers fall back to
/// the push payload when this fails.
Future<HostCard> ensureCallbackHost({
  String? expertDocumentId,
  String? userId,
}) => queryCache.fetchQuery<HostCard>(
  ListingKeys.callbackHost(expertDocumentId: expertDocumentId, userId: userId),
  () => ListingApi.findCallbackHost(
    expertDocumentId: expertDocumentId,
    userId: userId,
  ),
);

/// RN rule: a link to the viewer's own documentId or handler (or id).
bool _isOwnTarget(String target) {
  if (target.isEmpty) return false;
  final user = SessionStore.instance.value.user;
  return target == J.str(user?['documentId']) ||
      target == J.str(user?['handler']) ||
      target == J.str(user?['id']);
}

String? _ownDoc(bool own) =>
    own ? SessionStore.instance.value.userDocumentId : null;

QueryResult<T, ApiException> _withData<T>(
  QueryResult<T, ApiException> r,
  T data, {
  bool loading = false,
}) => QueryResult<T, ApiException>(
  data: data,
  dataUpdatedAt: r.dataUpdatedAt,
  error: r.error,
  errorUpdatedAt: r.errorUpdatedAt,
  isError: r.isError,
  isLoading: false,
  isFetching: r.isFetching || loading,
  isSuccess: r.data != null ? r.isSuccess : true,
  status: r.data != null ? r.status : QueryStatus.success,
  refetch: r.refetch,
  isInvalidated: r.isInvalidated,
  isRefetchError: r.isRefetchError,
);
