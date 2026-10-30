import 'dart:async';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/call_ui_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/instant_call/instant_call_api.dart';
import '../../../api/instant_call/instant_call_models.dart';
import '../call_alerts.dart';
import '../call_billing.dart';
import '../call_analytics.dart';
import '../call_controller.dart';
import '../call_identity.dart';
import '../call_navigator.dart';
import '../call_payload.dart';
import '../call_permissions.dart';
import '../call_platform.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../call_timers.dart';
import '../engine/call_engine.dart';
import '../native/native_call_marks.dart';
import 'end_flow.dart';
import 'outgoing_flow.dart';

abstract final class InstantCallFlow {
  static bool _placing = false;

  /// Hosts the current instant call has rung so far (analytics).
  static int _attempts = 0;

  /// The server searches this long by default (`max_total_ring_seconds`).
  static const defaultSearchSeconds = 120;

  /// [maxRingSeconds]: the server's search window (`/instant-call/config`);
  /// the caller waits that long, then a margin, for a host.
  static Future<bool> place({bool video = false, int? maxRingSeconds}) async {
    CallRuntime.ensureStarted();
    if (_placing) return false;
    final now = CallController.instance.value;
    if (now.phase.isActive) {
      CallUiEvents.instantFailed(video: video, reason: 'call_in_progress');
      return false;
    }
    if (now.phase == CallPhase.ended) CallController.instance.reset();
    _placing = true;
    CallUiEvents.instantRequested(video: video);
    try {
      return await _place(video, maxRingSeconds);
    } catch (e) {
      Log.w('InstantCallFlow', 'place: $e');
      CallUiEvents.instantFailed(
        video: video,
        reason: 'exception',
        error: Analytics.errorCode(e),
      );
      return false;
    } finally {
      _placing = false;
    }
  }

  static Future<bool> _place(bool video, int? maxRingSeconds) async {
    final callerId = CallIdentity.userId;
    if (callerId == null) {
      CallUiEvents.instantFailed(video: video, reason: 'missing_participants');
      await CallAlerts.show(
        title: CallFlowKeys.unableTitle,
        message: 'call:errors.missing_participants',
      );
      return false;
    }
    if (!await CallPermissions.ensureForOutgoing(video: video)) {
      CallUiEvents.instantFailed(video: video, reason: 'permission_denied');
      return false;
    }

    final InitiatedInstantCall started;
    try {
      started = await InstantCallApi.initiate(
        callerId: int.tryParse(callerId) ?? callerId,
        type: video ? 'videoCall' : 'voiceCall',
      );
    } on ApiException catch (e) {
      CallUiEvents.instantFailed(
        video: video,
        reason: OutgoingFlow.failureReason(e),
        error: Analytics.errorCode(e),
      );
      await CallAlerts.error(e, title: CallFlowKeys.failedTitle);
      return false;
    }

    final firstHost = started.currentHost;
    _attempts = firstHost?.userId == null ? 0 : 1;
    final call = CallSession(
      role: CallRole.caller,
      callId: started.sessionId,
      callDocumentId: started.sessionId,
      channelName: started.channelName,
      token: CallPayload.repairToken(started.callerToken),
      isVideo: video,
      remote: CallPeer(
        id: firstHost?.userId,
        name: firstHost?.name,
        avatarUrl: firstHost?.profilePic,
      ),
      callerId: callerId,
      callerDocId: CallIdentity.userDocumentId,
      callerIsCompany: CallIdentity.isCompany,
      sentAt: DateTime.now(),
      isInstantCall: true,
      instantCallSessionId: started.sessionId,
    );
    // The balance cap (hang up before the wallet runs out) needs the rate
    // the caller pays: Talk Now's own.
    final rate = started.callerRate;
    if (rate != null && rate > 0) {
      CallBilling.rememberRate(started.sessionId, rate);
    }
    CallController.instance.startOutgoing(call);
    unawaited(_markOutgoing(CallController.instance.value));
    // The server says when its search failed (`INSTANT_CALL_FAILED`); if
    // that push is lost, give up once its window is surely over.
    final window = Duration(
      seconds: (maxRingSeconds ?? defaultSearchSeconds) + 15,
    );
    CallTimers.instance.arm(CallTimers.noAnswer, window, () {
      final now = CallController.instance.value;
      if (now.isSameCall(started.sessionId) && now.phase.isPreConnect) {
        unawaited(EndFlow.hangup(reason: CallEndReason.noAnswer));
      }
    });
    CallNavigator.toCall();
    unawaited(_joinAndRing(call));
    return true;
  }

  static Future<void> _markOutgoing(CallSession call) async {
    try {
      await CallPlatform.instance.markOutgoing(call);
    } catch (e) {
      Log.w('InstantCallFlow', 'markOutgoing: $e');
    }
  }

  static Future<void> _joinAndRing(CallSession call) async {
    final uid = call.localUid;
    if (uid != null) {
      await CallEngine.instance.join(
        channel: call.channelName ?? '',
        token: call.token ?? '',
        uid: uid,
        video: call.isVideo,
      );
    }
    final now = CallController.instance.value;
    if (now.isSameCall(call.callId) &&
        now.phase.isPreConnect &&
        !CallEngine.instance.hasRemote) {
      await CallRingtone.play(CallTone.ringback);
    }
  }

  static void onHostChanged(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall || !session.phase.isPreConnect) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    final host = InstantCallHost.fromPush(data);
    if (host.userId == null) return;
    if (host.userId != session.remote.id) {
      _attempts++;
      CallUiEvents.instantHostAssigned(
        callId: session.callId,
        attempt: _attempts,
      );
    }
    CallController.instance.update(
      (s) => s.copyWith(
        remote: CallPeer(
          id: host.userId,
          name: host.name,
          avatarUrl: host.profilePic,
        ),
      ),
    );
  }

  static void onConnected(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    final hostId = data['hostUserId']?.toString();
    final hostName = data['hostName']?.toString();
    final hostPic = data['hostProfilePic']?.toString();
    // The call record the backend created: Callend bills it.
    final record = CallPayload.read(data, const ['callId']);
    final ring = session.callId;
    if (record != null && ring != null) {
      unawaited(NativeCallMarks.saveServerCallId(ring, record));
    }
    CallUiEvents.instantMatched(callId: session.callId, hostUserId: hostId);
    CallController.instance.update(
      (s) => s.copyWith(
        receiverId: hostId,
        serverCallId: record,
        remote: hostId == null
            ? null
            : CallPeer(
                id: hostId,
                name: hostName ?? s.remote.name,
                avatarUrl: hostPic ?? s.remote.avatarUrl,
              ),
      ),
    );
  }

  static void onFailed(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    // Only a search can fail: a call a host already answered goes on.
    if (!session.phase.isPreConnect) return;
    CallUiEvents.instantNoHost(callId: session.callId, attempts: _attempts);
    // Nobody picked up: CallAnalytics files it as not answered.
    CallAnalytics.reason(session.callId, CallEndReason.noAnswer);
    CallController.instance.end();
  }

  /// Ends the caller's search (`/instant-call/cancel`). [call]: the call
  /// that just ended (the live slot may already be reset by then).
  static Future<void> cancel([CallSession? call]) async {
    final session = call ?? CallController.instance.value;
    // The caller's search only (the server refuses anyone else's cancel).
    if (!session.isInstantCall || !session.isCaller) return;
    final sessionId = session.instantCallSessionId;
    if (sessionId == null) return;
    // Every hang-up comes through here; only one before an answer counts.
    if (!session.everConnected) {
      CallUiEvents.instantCancelled(
        callId: session.callId,
        attempts: _attempts,
      );
    }
    try {
      await InstantCallApi.cancel(sessionId);
    } catch (e) {
      Log.w('InstantCallFlow', 'cancel: $e');
    }
  }
}
