import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fquery_core/fquery_core.dart' show QueryStatus;

import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'host_index.dart';
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
/// [userDocumentId]; [handler] is the last fallback). A host already seen
/// this session comes from [HostIndex] without a request.
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
    () => _indexed(
      HostIndex.find(
        expertDocumentId: expertId,
        userDocumentId: userId,
        handler: handler,
      ),
      () => ListingApi.findHost(
        expertDocumentId: expertId,
        userDocumentId: userId,
        handler: handler,
      ),
    ),
    context: context,
    enabled: enabled && (expertId.isNotEmpty || userId.isNotEmpty),
    staleDuration: HostIndex.freshFor,
  );
}

/// What the profile sheet shows for [host]: a full card as it is; a summary
/// (call log, favourites, nudge) upgraded at once from [HostIndex] when the
/// host was seen this session, else fetched while the summary shows. A
/// stale index entry renders, then refreshes in place.
({HostCard profile, bool waiting, ApiException? error, VoidCallback retry})
useHostSheetDetail(BuildContext context, HostCard host) {
  final hit = useMemoized(
    () => host.hasFullProfile
        ? null
        : HostIndex.find(
            expertDocumentId: host.expertProfileDocumentId,
            userDocumentId: host.userDocumentId,
            handler: host.handler,
          ),
    [host],
  );
  final shown = hit?.card ?? host;
  final hasIds =
      (host.expertProfileDocumentId ?? '').isNotEmpty ||
      (host.userDocumentId ?? '').isNotEmpty;
  final refresh = !shown.hasFullProfile || hit?.fresh == false;
  final detail = useHostDetail(
    context,
    expertDocumentId: host.expertProfileDocumentId,
    userDocumentId: host.userDocumentId,
    handler: host.handler.isEmpty ? null : host.handler,
    enabled: refresh && hasIds,
  );
  final profile = detail.data ?? shown;
  final missing = !profile.hasFullProfile && refresh && hasIds;
  return (
    profile: profile,
    waiting: missing && detail.data == null && !detail.isError,
    error: missing && detail.data == null ? detail.error : null,
    retry: () => detail.refetch(),
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
    () => _indexed(
      own ? null : HostIndex.findLink(target),
      () => ListingApi.findHostByLink(target, ownUserDocumentId: _ownDoc(own)),
      seed: !own,
    ),
    context: context,
    enabled: enabled && target.isNotEmpty,
    staleDuration: HostIndex.freshFor,
  );
}

/// `GET /search` for [query] (debounce in the UI), with the verification
/// badges merged in once the hits' batched full-card read lands (which also
/// fills [HostIndex]: a tapped hit opens without waiting). While a new query loads,
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
  final hosts = useApiQuery<Map<String, HostCard>>(
    ListingKeys.searchHosts(ids),
    () async {
      final found = await SearchApi.fetchHosts(ids);
      HostIndex.seed(found.values);
      return found;
    },
    context: context,
    enabled: ids.isNotEmpty,
    staleDuration: StaleTime.short,
  );

  final previous = useRef<SearchResults?>(null);
  if (q.isEmpty) previous.value = null;
  final fresh = result.data;
  final hostData = hosts.data;
  final merged = useMemoized(
    () => fresh?.withBadges({
      for (final MapEntry(:key, :value) in (hostData ?? const {}).entries)
        key: HostBadges.of(value),
    }),
    [fresh, hostData],
  );
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

/// Warms [HostIndex] with the hosts behind a list's rows (call log
/// counterparts by user documentId, favourites by expert-profile
/// documentId) in ONE batched read, so tapping any row opens its profile at
/// once. Hosts already fresh in the index are not asked for again.
void useWarmHostIndex(
  BuildContext context, {
  List<String> userDocumentIds = const [],
  List<String> expertDocumentIds = const [],
}) {
  List<String> missing(List<String> ids, bool byUser) => [
    for (final id in {...ids})
      if (id.isNotEmpty &&
          HostIndex.find(
                userDocumentId: byUser ? id : null,
                expertDocumentId: byUser ? null : id,
              )?.fresh !=
              true)
        id,
  ];
  final users = useMemoized(() => missing(userDocumentIds, true), [
    userDocumentIds.join('|'),
  ]);
  final experts = useMemoized(() => missing(expertDocumentIds, false), [
    expertDocumentIds.join('|'),
  ]);
  Future<int> warm(List<String> ids, bool byUser) async {
    final hosts = await ListingApi.fetchCards(ids, byUser: byUser);
    HostIndex.seed(hosts);
    return hosts.length;
  }

  useApiQuery<int>(
    ListingKeys.warmHosts('user', users),
    () => warm(users, true),
    context: context,
    enabled: users.isNotEmpty,
    staleDuration: HostIndex.freshFor,
  );
  useApiQuery<int>(
    ListingKeys.warmHosts('expert', experts),
    () => warm(experts, false),
    context: context,
    enabled: experts.isNotEmpty,
    staleDuration: HostIndex.freshFor,
  );
}

/// The host behind these ids if seen this session, without a request (any
/// age: show it, the sheet refreshes a stale one). Open the profile with it
/// at once; null means a lookup is needed.
HostCard? peekHost({
  String? expertDocumentId,
  String? userDocumentId,
  String? userId,
  String? handler,
}) => HostIndex.find(
  expertDocumentId: expertDocumentId,
  userDocumentId: userDocumentId,
  userId: userId,
  handler: handler,
)?.card;

/// [peekHost] for a shared link / `openUserId` target (never the viewer's
/// own: that one goes through the owner lookup).
HostCard? peekHostLink(String targetId) =>
    _isOwnTarget(targetId.trim()) ? null : HostIndex.findLink(targetId)?.card;

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
    () => _indexed(
      HostIndex.find(
        expertDocumentId: expertId,
        userDocumentId: userId,
        handler: handler,
      ),
      () => ListingApi.findHost(
        expertDocumentId: expertId,
        userDocumentId: userId,
        handler: handler,
      ),
    ),
    staleDuration: HostIndex.freshFor,
  );
}

/// Outside widgets (deep links, post-login actions).
Future<HostCard> ensureHostByLink(String targetId) {
  final target = targetId.trim();
  final own = _isOwnTarget(target);
  return queryCache.fetchQuery<HostCard>(
    ListingKeys.hostByLink(target, own),
    () => _indexed(
      own ? null : HostIndex.findLink(target),
      () => ListingApi.findHostByLink(target, ownUserDocumentId: _ownDoc(own)),
      seed: !own,
    ),
    staleDuration: HostIndex.freshFor,
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
    () => _indexed(
      own
          ? null
          : HostIndex.find(
              userDocumentId: userDocumentId,
              expertDocumentId: expertDocumentId,
              userId: userId,
            ),
      () => ListingApi.findProfile(
        userDocumentId: userDocumentId,
        userId: userId,
        expertDocumentId: expertDocumentId,
        ownUserDocumentId: _ownDoc(own),
      ),
      seed: !own,
    ),
    staleDuration: HostIndex.freshFor,
  );
}

/// Outside widgets (the `PING_CLIENT` push handler). Callers fall back to
/// the push payload when this fails.
Future<HostCard> ensureCallbackHost({
  String? expertDocumentId,
  String? userId,
}) => queryCache.fetchQuery<HostCard>(
  ListingKeys.callbackHost(expertDocumentId: expertDocumentId, userId: userId),
  () => _indexed(
    HostIndex.find(expertDocumentId: expertDocumentId, userId: userId),
    () => ListingApi.findCallbackHost(
      expertDocumentId: expertDocumentId,
      userId: userId,
    ),
  ),
  staleDuration: HostIndex.freshFor,
);

/// A fresh [hit] without a request, else [lookup] (its result goes into
/// [HostIndex] unless [seed] is false: the viewer's own pending profile).
Future<HostCard> _indexed(
  HostHit? hit,
  Future<HostCard> Function() lookup, {
  bool seed = true,
}) async {
  if (hit != null && hit.fresh) return hit.card;
  final host = await lookup();
  if (seed) HostIndex.seed([host]);
  return host;
}

/// RN rule: a link to the viewer's own documentId or handler (or user id,
/// or their expert profile's documentId / handler).
bool _isOwnTarget(String target) {
  if (target.isEmpty) return false;
  final session = SessionStore.instance.value;
  final user = session.user, expert = session.expert;
  final lower = target.toLowerCase();
  return target == J.str(user?['documentId']) ||
      target == J.str(user?['id']) ||
      target == J.str(expert?['documentId']) ||
      lower == J.str(user?['handler'])?.toLowerCase() ||
      lower == J.str(expert?['handler'])?.toLowerCase();
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
