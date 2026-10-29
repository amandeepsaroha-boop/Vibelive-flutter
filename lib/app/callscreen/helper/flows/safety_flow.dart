import '../../../../core/network/api_client.dart';
import '../../../../core/network/strapi.dart';
import '../../../../core/query/query_client.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_keys.dart';
import '../../../api/callscreen/review_api.dart';
import '../../../api/client/block_api.dart';
import '../../../api/client/client_keys.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/component/report_api.dart';
import '../../../api/homescreen/home_keys.dart';
import '../../../api/listingflow/listing_keys.dart';
import '../call_actions.dart';
import '../call_analytics.dart';
import '../call_controller.dart';
import '../call_identity.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../state/call_constants.dart';
import 'end_flow.dart';

/// Report / block from the call screens and the post-call rating (RN
/// CallingScreen `runSafetyAction`, IncomingCallScreen safety rows,
/// FeedBackModal).
abstract final class SafetyFlow {
  /// The call the screens are about: live, or the one that just ended.
  static CallSession get _call {
    final s = CallController.instance.value;
    return s.callId != null ? s : CallRuntime.lastCall;
  }

  /// The other person's documentId (else numeric id).
  static String? _remoteKey(CallSession s) =>
      s.remote.documentId ??
      (s.isCaller ? null : s.callerDocId) ??
      s.remote.id ??
      (s.isCaller ? s.receiverId : s.callerId);

  /// In-call "Report this call": report, then hang up.
  static Future<CallSafetyOutcome> reportDuringCall() =>
      _duringCall(block: false);

  /// In-call "Block": block, then hang up.
  static Future<CallSafetyOutcome> blockDuringCall() =>
      _duringCall(block: true);

  static Future<CallSafetyOutcome> _duringCall({required bool block}) async {
    final s = _call;
    final target = _remoteKey(s);
    final reporter = CallIdentity.userDocumentId ?? CallIdentity.userId;
    CallSafetyOutcome outcome;
    if (target == null || (!block && reporter == null)) {
      outcome = CallSafetyOutcome.noTarget;
    } else {
      final ok = block
          ? await SafetyFlow.block(target, CallWire.blockedDuringCall)
          : await report(target, CallWire.reportedDuringCall);
      outcome = ok ? CallSafetyOutcome.done : CallSafetyOutcome.failed;
    }
    await EndFlow.hangup(
      reason: block ? CallEndReason.safetyBlock : CallEndReason.safetyReport,
    );
    return outcome;
  }

  /// Rating sheet "Block this User" (RN: no reason).
  static Future<bool> blockAfterCall() => block(_remoteKey(_call), null);

  /// `POST /user-blocks`; the person disappears from every list. Never
  /// throws.
  static Future<bool> block(String? targetUserId, String? reason) async {
    if (targetUserId == null || targetUserId.isEmpty) return false;
    try {
      await ApiClient.guard(
        () => BlockApi.blockUser(BlockUserInput(targetUserId, reason: reason)),
      );
      queryCache.invalidateAll(const [
        ClientKeys.blockedUsers,
        ClientKeys.favorites,
        HomeKeys.all,
        ListingKeys.all,
        CallKeys.history,
      ]);
      return true;
    } catch (e) {
      Log.w('SafetyFlow', 'block failed: $e');
      return false;
    }
  }

  /// `POST /reports` with [note]. Never throws.
  static Future<bool> report(String? reportedUserId, String note) async {
    final reporter = CallIdentity.userDocumentId ?? CallIdentity.userId;
    if (reporter == null || reportedUserId == null) return false;
    try {
      await ApiClient.guard(
        () => ReportApi.submit(
          ReportInput(
            reporterId: reporter,
            reportedUserId: reportedUserId,
            note: note,
          ),
        ),
      );
      return true;
    } catch (e) {
      Log.w('SafetyFlow', 'report failed: $e');
      return false;
    }
  }

  /// Rating sheet submit (caller, connected call). The expert-profile id
  /// is resolved from the host's user like RN `fetchUserWithExpert`. Never
  /// throws.
  static Future<void> submitFeedback({
    required int rating,
    String comments = '',
  }) async {
    final s = _call;
    final callId = s.callId;
    final user = CallIdentity.userDocumentId ?? CallIdentity.userId;
    if (callId == null || user == null) return;
    try {
      final expertId = await _expertProfileId(s);
      await ApiClient.guard(
        () => ReviewApi.submit(
          ReviewInput(
            expertId: expertId,
            userId: user,
            rating: rating,
            comments: comments,
            callId: int.tryParse(callId) ?? callId,
          ),
        ),
      );
      // Same invalidation as `useSubmitReview`.
      queryCache.invalidateAll([
        CallKeys.expertReviewsAll,
        HomeKeys.all,
        ListingKeys.all,
        CallKeys.callReview(callId),
      ]);
    } catch (e) {
      Log.w('SafetyFlow', 'feedback failed: $e');
    }
  }

  static Future<String?> _expertProfileId(CallSession s) async {
    final userDoc = s.remote.documentId;
    if (userDoc != null) {
      try {
        final found = await ensureUserWithExpert(userDoc);
        final id = J.str(found.expert?['documentId']);
        if (id != null) return id;
      } catch (e) {
        Log.w('SafetyFlow', 'expert lookup failed: $e');
      }
    }
    // The initiate response / push carries the expert-profile documentId.
    return s.receiverDocId;
  }
}
