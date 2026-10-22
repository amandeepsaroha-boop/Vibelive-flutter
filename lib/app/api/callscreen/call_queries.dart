import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_inflight.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../homescreen/home_keys.dart';
import '../listingflow/listing_keys.dart';
import 'call_api.dart';
import 'call_errors.dart';
import 'call_keys.dart';
import 'call_models.dart';
import 'pending_decline_queue.dart';
import 'review_api.dart';

// ── Call history (Logs tab) ──────────────────────────────────────────────

/// What [useCallHistory] gives the Logs tab.
class CallHistoryFeed {
  const CallHistoryFeed({
    required this.items,
    required this.firstPage,
    required this.hasMore,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.loadMore,
    required this.refresh,
  });

  /// Newest first, each call once across pages.
  final List<CallHistoryItem> items;

  /// Page 1 (disk copy first): drives the list's loading / error state.
  final QueryResult<CallHistoryPage, ApiException> firstPage;

  /// The server has more pages.
  final bool hasMore;
  final bool isLoadingMore;

  /// Last next-page load failed; [loadMore] retries it.
  final ApiException? loadMoreError;

  /// Loads the next page (call from the list end, and from a retry button).
  final VoidCallback loadMore;

  /// Pull to refresh: page 1 now (throws [ApiException]), further pages in
  /// the background.
  final Future<void> Function() refresh;
}

/// Calls of the signed-in user (or [userDocumentId]). Page 1 is persisted so
/// the tab renders instantly on launch; pages 2+ load on demand.
CallHistoryFeed useCallHistory(
  BuildContext context, {
  String? userDocumentId,
  String? viewerRole,
}) {
  final session = useValueListenable(SessionStore.instance);
  final docId = J.str(userDocumentId) ?? session.userDocumentId;
  final role = viewerRole ?? J.str(session.user?['role']);
  final hasUser = docId != null;
  final id = docId ?? '';

  final first = usePersistedQuery<CallHistoryPage>(
    CallKeys.historyFirstPage(id),
    () => CallApi.fetchHistory(id),
    context: context,
    enabled: hasUser,
    staleDuration: StaleTime.short,
    toJson: (page) => page.toJson(),
    fromJson: CallHistoryPage.fromJson,
  );
  final firstPage = first.data;
  final firstHasMore = firstPage?.hasMore ?? false;

  // Pages 2+ start loading only once the list reaches its end.
  final moreFor = useState<String?>(null);
  final wantsMore = hasUser && moreFor.value == docId && firstHasMore;

  final more = useApiInfiniteQuery<CallHistoryPage>(
    CallKeys.historyMorePages(id),
    (page) => CallApi.fetchHistory(id, page: page),
    context: context,
    initialPage: 2,
    hasMore: (last) => last.hasMore,
    enabled: wantsMore,
    staleDuration: StaleTime.short,
  );

  // fquery's infinite observer only fetches on enable when it has no data:
  // refresh pages kept from an earlier visit once they're shown again.
  useEffect(() {
    final updatedAt = more.dataUpdatedAt;
    final stale =
        more.isInvalidated ||
        updatedAt == null ||
        DateTime.now().difference(updatedAt) > StaleTime.short;
    if (wantsMore && !more.isLoading && stale) {
      WidgetsBinding.instance.addPostFrameCallback((_) => more.refetch());
    }
    return null;
  }, [wantsMore]);

  final morePages = wantsMore ? more.data?.pages : null;
  final items = useMemoized(
    () => [
      for (final call in CallHistoryPage.merge([?firstPage, ...?morePages]))
        CallHistoryItem(call, viewerDocumentId: id, viewerRole: role),
    ],
    [firstPage, morePages, id, role],
  );

  void loadMore() {
    if (!firstHasMore) return;
    if (!wantsMore) {
      moreFor.value = docId;
      return;
    }
    if (more.isFetching) return;
    if (more.data == null) {
      more.refetch();
    } else if (more.hasNextPage) {
      more.fetchNextPage();
    }
  }

  Future<void> refresh() async {
    if (!hasUser) return;
    queryCache.invalidateAll([CallKeys.historyMorePages(id)]);
    await ensureCallHistory(id, force: true);
  }

  return CallHistoryFeed(
    items: items,
    firstPage: first,
    hasMore: firstHasMore && (morePages == null || more.hasNextPage),
    isLoadingMore: wantsMore && more.isFetchingNextPage,
    loadMoreError: wantsMore && more.isError ? more.error : null,
    loadMore: loadMore,
    refresh: refresh,
  );
}

/// Page 1 of the history outside widgets (startup prefetch after login) —
/// also refreshes the disk copy.
Future<CallHistoryPage> ensureCallHistory(
  String userDocumentId, {
  bool force = false,
}) {
  final key = CallKeys.historyFirstPage(userDocumentId);
  return queryCache.fetchQuery<CallHistoryPage>(key, () async {
    final page = await CallApi.fetchHistory(userDocumentId);
    QueryPersist.write(key, page.toJson());
    return page;
  }, staleDuration: force ? StaleTime.none : StaleTime.short);
}

// ── Call status ──────────────────────────────────────────────────────────

QueryResult<CallStatus, ApiException> useCallStatus(
  BuildContext context,
  String? callId, {
  bool enabled = true,
  Duration? refetchInterval,
}) {
  final id = J.str(callId) ?? '';
  return useApiQuery<CallStatus>(
    CallKeys.statusOf(id),
    () => CallApi.fetchStatus(id),
    context: context,
    enabled: enabled && id.isNotEmpty,
    staleDuration: StaleTime.none,
    refetchInterval: refetchInterval,
  );
}

Future<CallStatus> ensureCallStatus(String callId) =>
    queryCache.fetchQuery<CallStatus>(
      CallKeys.statusOf(callId),
      () => CallApi.fetchStatus(callId),
      staleDuration: StaleTime.none,
    );

/// Cold-start guard (RN root layout): don't route into a call from a push or
/// deep link that the backend already closed. Optimistic on purpose: an
/// error, or no answer within [timeout], counts as "still live" so a real
/// call is never dropped.
Future<bool> isCallClosedOnServer(
  String callId, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (callId.isEmpty) return false;
  try {
    return (await ensureCallStatus(callId).timeout(timeout)).isClosed;
  } on Exception {
    return false;
  }
}

// ── Call signaling ───────────────────────────────────────────────────────

typedef RingingAck = ({String callId, String receiverId});

/// Errors: check `isUserBusy` for the busy alert; `localizedMessage` covers
/// the rest.
MutationResult<InitiatedCall, ApiException, InitiateCallInput> useInitiateCall({
  void Function(InitiatedCall call)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<InitiatedCall, InitiateCallInput>(
  CallApi.initiateCall,
  invalidates: const [CallKeys.history],
  onSuccess: (call, _) => onSuccess?.call(call),
  onError: (e, _) => onError?.call(e),
);

/// Non-blocking for the accept flow; `isBenignRingingAck` errors are noise.
MutationResult<void, ApiException, RingingAck> useRingingAck({
  void Function(ApiException error)? onError,
}) => useApiMutation<void, RingingAck>(
  (v) => CallApi.sendRingingAck(callId: v.callId, receiverId: v.receiverId),
  invalidates: const [CallKeys.status],
  onError: (e, _) => onError?.call(e),
);

MutationResult<UpdateCallResult, ApiException, CallStatusUpdate>
useUpdateCallStatus({
  void Function(UpdateCallResult result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<UpdateCallResult, CallStatusUpdate>(
  CallApi.updateStatus,
  invalidates: const [CallKeys.status],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);

/// End / decline / cancel from a screen that stays mounted. A screen that
/// leaves right away (hangup) should use [CallRequests.endCall].
MutationResult<void, ApiException, CallEndInput> useEndCall({
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, CallEndInput>(
  CallApi.endCall,
  invalidates: const [CallKeys.history, CallKeys.status],
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);

/// Variables: the client's public-user documentId.
MutationResult<void, ApiException, String> usePingClient({
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, String>(
  CallApi.pingClient,
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);

/// Call writes for non-widget code (push handlers, CallKit actions, app
/// lifecycle): the same requests as the hooks, with the same invalidation.
/// (The user actions of the call screens are `CallActions` in
/// `callscreen/helper/call_actions.dart`.)
abstract final class CallRequests {
  static Future<InitiatedCall> initiateCall(InitiateCallInput input) async {
    final call = await ApiClient.guard(() => CallApi.initiateCall(input));
    queryCache.invalidateAll(const [CallKeys.history]);
    return call;
  }

  /// Never throws, never blocks a ring: RN only logged a failed ack (409
  /// "not in pending state", or the 500 Strapi 5 may answer instead).
  /// False when it failed.
  static Future<bool> sendRingingAck({
    required String callId,
    required String receiverId,
  }) async {
    try {
      await ApiClient.guard(
        () => CallApi.sendRingingAck(callId: callId, receiverId: receiverId),
      );
      queryCache.invalidateAll([CallKeys.statusOf(callId)]);
      return true;
    } on ApiException catch (e) {
      if (!e.isBenignRingingAck) Log.w('CallRequests', 'ringing ack: $e');
      return false;
    }
  }

  static Future<UpdateCallResult> updateStatus(CallStatusUpdate update) async {
    final result = await ApiClient.guard(() => CallApi.updateStatus(update));
    queryCache.invalidateAll([CallKeys.statusOf(update.callId)]);
    return result;
  }

  static Future<void> endCall(CallEndInput input) async {
    await ApiClient.guard(() => CallApi.endCall(input));
    queryCache.invalidateAll(CallKeys.afterCallChange(input.callId));
  }

  /// Decline from the native call UI / notification (often while locked).
  /// A failure is queued for replay instead of lost (RN headless task), so
  /// this never throws. Returns false when the decline was queued.
  static Future<bool> declineOrQueue(CallEndInput input) async {
    try {
      await endCall(input);
      return true;
    } on ApiException catch (e) {
      // Already closed server-side: nothing left to tell the backend.
      if (e.isBenignDecline) return true;
      await PendingDeclineQueue.enqueue(input);
      return false;
    }
  }

  /// Replays queued declines: call on app foreground and on each VoIP push.
  static Future<void> flushPendingDeclines() async {
    final sent = await PendingDeclineQueue.flush();
    if (sent > 0) queryCache.invalidateAll(const [CallKeys.history]);
  }
}

// ── Reviews ──────────────────────────────────────────────────────────────

/// Review left on a history call: the populated one when it has content,
/// else looked up. Only runs for calls that may have one
/// ([CallHistoryItem.mayHaveReview]).
QueryResult<Review?, ApiException> useCallReview(
  BuildContext context,
  CallHistoryItem item, {
  bool enabled = true,
}) {
  final call = item.call;
  return useApiQuery<Review?>(
    CallKeys.callReview(call.key),
    () async {
      final embedded = call.review;
      if (embedded != null && embedded.hasContent) return embedded;
      return ReviewApi.fetchForCall(call.key);
    },
    context: context,
    enabled: enabled && item.mayHaveReview && call.key.isNotEmpty,
    staleDuration: StaleTime.medium,
  );
}

/// An expert's reviews, newest first, [ReviewApi.expertPageSize] per page.
/// [expertId]: expert-profile documentId or numeric id.
InfiniteQueryResult<ReviewPage, ApiException, int> useExpertReviews(
  BuildContext context,
  String? expertId, {
  bool enabled = true,
}) {
  final id = J.str(expertId?.trim()) ?? '';
  return useApiInfiniteQuery<ReviewPage>(
    CallKeys.expertReviews(id),
    (page) => ReviewApi.fetchByExpert(id, page: page),
    context: context,
    hasMore: (last) => last.hasMore,
    enabled: enabled && id.isNotEmpty,
    staleDuration: StaleTime.short,
  );
}

/// Page 1 of [expertId]'s reviews, started with the profile sheet (in
/// parallel with everything else it loads). Same in-flight id as the
/// [useExpertReviews] first page, so the sheet joins it.
void prefetchExpertReviews(String? expertId) {
  final id = J.str(expertId?.trim()) ?? '';
  if (id.isEmpty) return;
  final key = CallKeys.expertReviews(id);
  if (queryCache.entry<InfiniteQueryData<ReviewPage, int>>(key)?.data != null) {
    return;
  }
  QueryInflight.run<ReviewPage>([
    ...key,
    '#page',
  ], () => ApiClient.guard(() => ReviewApi.fetchByExpert(id))).then((page) {
    // Kept when no sheet joined it (the sheet then finds it cached).
    if (queryCache.entry<InfiniteQueryData<ReviewPage, int>>(key)?.data ==
        null) {
      queryCache.setQueryData<InfiniteQueryData<ReviewPage, int>, ApiException>(
        key,
        (_) => InfiniteQueryData(pages: [page], pageParams: [1]),
      );
    }
  }, onError: (Object _) {});
}

/// After-call feedback and "Rate this call". Errors: `localizedMessage`.
MutationResult<Review, ApiException, ReviewInput> useSubmitReview({
  void Function(Review review)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<Review, ReviewInput>(
  ReviewApi.submit,
  // A review changes the host's rating on cards and the detail sheet.
  invalidates: const [CallKeys.expertReviewsAll, HomeKeys.all, ListingKeys.all],
  onSuccess: (review, input) {
    // The per-call key depends on the variables.
    final callId = J.str(input.callId);
    if (callId != null) queryCache.invalidateAll([CallKeys.callReview(callId)]);
    onSuccess?.call(review);
  },
  onError: (e, _) => onError?.call(e),
);
