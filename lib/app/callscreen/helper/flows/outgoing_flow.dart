import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_api.dart';
import '../../../api/callscreen/call_errors.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/call_queries.dart';
import '../../../api/listingflow/listing_models.dart';
import '../call_actions.dart';
import '../call_alerts.dart';
import '../call_billing.dart';
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
import '../state/call_constants.dart';
import 'end_flow.dart';

/// Who is being called and how (host card, callback sheet or redial).
@immutable
class OutgoingRequest {
  const OutgoingRequest({
    required this.receiverId,
    required this.video,
    this.receiverDocId,
    this.expertDocId,
    this.name,
    this.avatarUrl,
    this.isCompany = false,
    this.categoryId,
    this.ratePerMin,
  });

  /// Profile path: RN sent the fallback category for every host card call.
  factory OutgoingRequest.fromHost(HostCard host, {required bool video}) =>
      OutgoingRequest(
        receiverId: host.receiverId?.toString(),
        video: video,
        receiverDocId: host.userDocumentId,
        expertDocId: host.expertProfileDocumentId,
        name: host.name,
        avatarUrl: host.images.firstOrNull ?? host.cardImage,
        categoryId: CallWire.profileCategoryId,
        ratePerMin: video ? host.vPrice : host.aPrice,
      );

  /// Callback sheet (`categoryId: null`) or history redial (the old call's
  /// category).
  factory OutgoingRequest.fromTarget(CallTarget t, {required bool video}) =>
      OutgoingRequest(
        receiverId: t.receiverId,
        video: video,
        receiverDocId: t.receiverDocId,
        name: t.name,
        avatarUrl: t.avatarUrl,
        isCompany: t.isCompany,
        categoryId: t.categoryId,
        ratePerMin: t.ratePerMin?.toDouble(),
      );

  /// Numeric public-user id of the person called (their Agora uid).
  final String? receiverId;
  final bool video;

  /// Their public-user documentId (Discover re-opens it after the call).
  final String? receiverDocId;

  /// Their expert-profile documentId, when known.
  final String? expertDocId;
  final String? name;
  final String? avatarUrl;
  final bool isCompany;
  final String? categoryId;

  /// Host rate for this call type (max duration); null = look it up.
  final double? ratePerMin;
}

/// Placing a call (RN DiscoveryScreen `handleInitiateCall`, CallbackModal
/// `initiateCallTo`, explore `callExpertFromLog`).
abstract final class OutgoingFlow {
  static bool _placing = false;

  /// Permission gate → `/initiateCall` → busy / invalid / failure alerts
  /// with RN copy → the call (joined while it rings) → `/call`. Never
  /// throws; false when no call started.
  static Future<bool> place(OutgoingRequest r) async {
    CallRuntime.ensureStarted();
    if (_placing) return false; // E-74 double tap
    final now = CallController.instance.value;
    // One call at a time (decision 17).
    if (now.phase.isActive) return false;
    // The previous call's summary is still up (its screen would be reused
    // for this call): finish it first. Its own exit is ignored from now on
    // (`EndFlow.exitToHome` checks the call id).
    if (now.phase == CallPhase.ended) CallController.instance.reset();
    _placing = true;
    try {
      return await _place(r);
    } catch (e) {
      Log.w('OutgoingFlow', 'place: $e');
      return false;
    } finally {
      _placing = false;
    }
  }

  static Future<bool> _place(OutgoingRequest r) async {
    final callerId = CallIdentity.userId;
    final receiverId = r.receiverId;
    if (callerId == null || receiverId == null || receiverId.isEmpty) {
      await CallAlerts.show(
        title: CallFlowKeys.unableTitle,
        message: CallErrorKeys.missingParticipants,
      );
      return false;
    }
    if (!await CallPermissions.ensureForOutgoing(video: r.video)) return false;

    final InitiatedCall started;
    try {
      started = await CallRequests.initiateCall(
        InitiateCallInput(
          callerId: int.tryParse(callerId) ?? callerId,
          receiverId: int.tryParse(receiverId) ?? receiverId,
          type: r.video ? CallType.video : CallType.voice,
          role: CallIdentity.role,
          categoryId: r.categoryId,
        ),
      );
    } on ApiException catch (e) {
      // Busy is an answer, not a call: never Callend it (E-82).
      await CallAlerts.error(
        e,
        title: e.isUserBusy ? CallFlowKeys.busyTitle : CallFlowKeys.failedTitle,
      );
      return false;
    }

    final responseDoc = started.receiverDocId;
    final call = CallSession(
      role: CallRole.caller,
      callId: started.callId,
      callDocumentId: started.callDocumentId,
      channelName: started.channelName,
      token: CallPayload.repairToken(started.callerToken),
      isVideo: r.video,
      remote: CallPeer(
        id: receiverId,
        documentId: r.receiverDocId,
        name: r.name,
        avatarUrl: r.avatarUrl,
        isCompany: r.isCompany,
      ),
      callerId: callerId,
      receiverId: receiverId,
      callerDocId: CallIdentity.userDocumentId,
      // `receiverDocId` is the expert-profile documentId ('Null' without).
      receiverDocId:
          (responseDoc == null || responseDoc.toLowerCase() == 'null')
          ? r.expertDocId
          : responseDoc,
      callerIsCompany: CallIdentity.isCompany,
      sentAt: DateTime.now(),
    );
    final rate = r.ratePerMin;
    if (rate != null) CallBilling.rememberRate(started.callId, rate);
    CallController.instance.startOutgoing(call);
    // Android: the ongoing-call service must start while the app is in
    // front (Android 12+ refuses it from the background).
    unawaited(_markOutgoing(CallController.instance.value));
    CallTimers.instance.arm(CallTimers.noAnswer, CallTimings.noAnswer, () {
      final now = CallController.instance.value;
      if (now.isSameCall(started.callId) && now.phase.isPreConnect) {
        unawaited(EndFlow.hangup()); // decision 7: a normal caller cancel
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
      Log.w('OutgoingFlow', 'markOutgoing: $e');
    }
  }

  /// The caller is in the channel while it rings (RN C5); the ringback
  /// starts once Agora owns the audio session (CE: iOS ringback mixes into
  /// it).
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

  @visibleForTesting
  static void debugReset() => _placing = false;
}
