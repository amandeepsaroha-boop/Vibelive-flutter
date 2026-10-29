import 'dart:async';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/instant_call/instant_call_api.dart';
import '../../../api/instant_call/instant_call_models.dart';
import '../call_alerts.dart';
import '../call_controller.dart';
import '../call_identity.dart';
import '../call_navigator.dart';
import '../call_payload.dart';
import '../call_permissions.dart';
import '../call_platform.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../engine/call_engine.dart';

abstract final class InstantCallFlow {
  static bool _placing = false;

  static Future<bool> place({bool video = false}) async {
    CallRuntime.ensureStarted();
    if (_placing) return false;
    final now = CallController.instance.value;
    if (now.phase.isActive) return false;
    if (now.phase == CallPhase.ended) CallController.instance.reset();
    _placing = true;
    try {
      return await _place(video);
    } catch (e) {
      Log.w('InstantCallFlow', 'place: $e');
      return false;
    } finally {
      _placing = false;
    }
  }

  static Future<bool> _place(bool video) async {
    final callerId = CallIdentity.userId;
    if (callerId == null) {
      await CallAlerts.show(
        title: CallFlowKeys.unableTitle,
        message: 'call:errors.missing_participants',
      );
      return false;
    }
    if (!await CallPermissions.ensureForOutgoing(video: video)) return false;

    final InitiatedInstantCall started;
    try {
      started = await InstantCallApi.initiate(
        callerId: int.tryParse(callerId) ?? callerId,
        type: video ? 'videoCall' : 'voiceCall',
      );
    } on ApiException catch (e) {
      await CallAlerts.error(e, title: CallFlowKeys.failedTitle);
      return false;
    }

    final firstHost = started.currentHost;
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
    CallController.instance.startOutgoing(call);
    unawaited(_markOutgoing(CallController.instance.value));
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
    CallController.instance.update((s) => s.copyWith(
      remote: CallPeer(
        id: host.userId,
        name: host.name,
        avatarUrl: host.profilePic,
      ),
    ));
  }

  static void onConnected(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    final hostId = data['hostUserId']?.toString();
    final hostName = data['hostName']?.toString();
    final hostPic = data['hostProfilePic']?.toString();
    if (hostId != null) {
      CallController.instance.update((s) => s.copyWith(
        receiverId: hostId,
        remote: CallPeer(
          id: hostId,
          name: hostName ?? s.remote.name,
          avatarUrl: hostPic ?? s.remote.avatarUrl,
        ),
      ));
    }
  }

  static void onFailed(Map<String, dynamic> data) {
    final session = CallController.instance.value;
    if (!session.isInstantCall) return;
    final sessionId = data['instantCallSessionId']?.toString();
    if (sessionId != session.instantCallSessionId) return;
    CallController.instance.end();
  }

  static Future<void> cancel() async {
    final session = CallController.instance.value;
    if (!session.isInstantCall) return;
    final sessionId = session.instantCallSessionId;
    if (sessionId == null) return;
    try {
      await InstantCallApi.cancel(sessionId);
    } catch (e) {
      Log.w('InstantCallFlow', 'cancel: $e');
    }
  }
}
