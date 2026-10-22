import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_queries.dart';
import '../call_controller.dart';
import '../call_device.dart';
import '../call_identity.dart';
import '../call_navigator.dart';
import '../call_payload.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../call_signals.dart';
import '../call_timers.dart';
import '../engine/call_engine.dart';
import '../engine/headless_join.dart';
import '../state/call_constants.dart';
import '../state/call_dedup.dart';
import '../state/call_store.dart';
import 'end_flow.dart';
import 'incoming_flow.dart';
import 'push_flow.dart';

/// System call UI events (CallKit / the Android call notification), app
/// lifecycle and the cold-start reconcile (native spec §2.7–2.8, mem #14,
/// #15). Whatever native already told the backend is never sent again.
abstract final class NativeFlow {
  static CallController get _calls => CallController.instance;

  /// Answered while the app was not in front: show `/call` on resume.
  static String? _routeOnResume;

  /// Answered from the system UI (RN `handleNativeAccept`, R7).
  static Future<void> onNativeAccepted(
    Map<String, dynamic> raw, {
    bool apiDone = false,
  }) async {
    CallRuntime.ensureStarted();
    final payload = CallPayload.parse(raw, selfId: CallIdentity.userId);
    // Never drive a call without join creds (RN deep-link rule).
    if (payload == null || !payload.hasJoinCreds) return;
    final callId = payload.callId;
    if (CallDedup.instance.isEnded(callId)) {
      EndFlow.endNativeOnce(callId); // E-17: a replayed accept of a dead call
      return;
    }
    IncomingFlow.clearNativeRinging(callId);
    CallDedup.instance
      ..markAnswered(callId)
      ..releaseClaims(callId);
    // Native sent `/UpdateCall` (iOS CXAnswerCallAction): never again.
    if (apiDone) CallDedup.instance.beginUpdateCall(callId);

    // Store population is gated by "same call", navigation is not (mem
    // #14 regression, E-22).
    final live = _calls.value;
    final same = live.isSameCall(callId);
    final answered =
        same &&
        (live.phase == CallPhase.accepted || live.phase == CallPhase.ongoing);
    if (!answered) {
      if (!same &&
          !_calls.receive(payload.session.copyWith(autoAccept: true))) {
        Log.w('NativeFlow', 'accept ignored: another call is live');
        return;
      }
      _calls.setAccepted();
      if (payload.ongoing) _calls.setConnected();
    }
    CallTimers.instance.cancel(CallTimers.incomingRing);
    await CallRingtone.silence();
    final s = _calls.value;
    // A rejoin (`__isOngoingCall`) never re-hits UpdateCall (RN §7.3).
    if (!payload.ongoing) {
      unawaited(IncomingFlow.reportOngoing(s, answering: true));
    }
    _join(s);
    IncomingFlow.armPeerFallback(callId);
    unawaited(IncomingFlow.noteLocked(callId)); // A9
    // Straight to /call, never via /call/incoming (mem #7); parked until the
    // router exists on a background launch, and again on resume.
    CallNavigator.toCall();
    if (!CallDevice.isForeground) {
      _routeOnResume = callId;
    } else {
      // Answered outside the app: the mic gate never ran (A2).
      unawaited(IncomingFlow.ensureMediaAccess(s));
    }
  }

  /// iOS: the `/UpdateCall` native sent at a CallKit answer failed (I1).
  /// Sent again from here with this device's id ([CallTimings.updateRetry]
  /// apart, while the call is not over); `alreadyOngoing` is fine (E-86).
  static Future<void> onNativeUpdateFailed(String callId) async {
    CallRuntime.ensureStarted();
    if (callId.isEmpty) return;
    for (final wait in [Duration.zero, ...updateRetryDelays]) {
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (CallDedup.instance.isEnded(callId)) return;
      final live = _calls.value;
      if (live.isSameCall(callId) && !live.phase.isActive) return;
      final call = live.isSameCall(callId)
          ? live
          : CallSession(
              role: CallRole.receiver,
              callId: callId,
              receiverId: CallIdentity.userId,
            );
      // Native's attempt holds the once-per-call slot: release it.
      CallDedup.instance.failUpdateCall(callId);
      if (await IncomingFlow.reportOngoing(call, answering: true)) return;
    }
    Log.w('NativeFlow', 'UpdateCall retries exhausted for $callId');
  }

  /// Waits between [onNativeUpdateFailed] attempts.
  @visibleForTesting
  static List<Duration> updateRetryDelays = CallTimings.updateRetry;

  /// iOS: CallKit owns the audio session even in front → parked join (3 s
  /// fallback). Android: the app was brought to the front → join now.
  static void _join(CallSession s) {
    final uid = s.localUid; // receiverId from the payload, never user.id
    final channel = s.channelName;
    final token = s.token;
    if (uid == null || channel == null || token == null) return;
    if (!CallDevice.isIOS && CallDevice.isForeground) {
      unawaited(
        CallEngine.instance.join(
          channel: channel,
          token: token,
          uid: uid,
          video: s.isVideo,
        ),
      );
      return;
    }
    unawaited(
      HeadlessJoin.instance.joinWhenAudioReady(
        channel: channel,
        token: token,
        uid: uid,
        video: s.isVideo,
      ),
    );
  }

  /// Declined on the system UI. [apiDone]: native sent Callend (iOS);
  /// otherwise it is sent here (ghost rings skipped, failures queued).
  static Future<void> onNativeDeclined(
    String callId, {
    bool apiDone = true,
    Map<String, dynamic>? payload,
  }) async {
    CallRuntime.ensureStarted();
    if (callId.isEmpty) return;
    IncomingFlow.clearNativeRinging(callId);
    CallDedup.instance
      ..markEnded(callId)
      ..releaseClaims(callId);
    final live = _calls.value;
    final same = live.isSameCall(callId);
    if (same && live.phase == CallPhase.ringing) _calls.reset();
    if (apiDone) return;
    final parsed = payload == null
        ? null
        : CallPayload.parse(payload, selfId: CallIdentity.userId)?.session;
    final call =
        (same ? live : parsed) ??
        CallSession(
          role: CallRole.receiver,
          callId: callId,
          receiverId: CallIdentity.userId,
        );
    final sent = call.sentAt;
    if (sent != null &&
        DateTime.now().difference(sent) > CallTimings.ghostDeclineTtl) {
      return; // E-15
    }
    await IncomingFlow.sendDecline(
      call.copyWith(role: CallRole.receiver, callId: callId),
    );
  }

  /// An answered call ended on the system UI: native sent Callend
  /// (mem #15). Leave Agora and end here, NO API.
  static Future<void> onNativeEnded(String callId) async {
    CallRuntime.ensureStarted();
    CallDedup.instance.markEnded(callId);
    final s = _calls.value;
    if (!s.isSameCall(callId) || !s.phase.isActive) return;
    EndFlow.endLocally(callId);
    await HeadlessJoin.instance.leave(); // E-44
  }

  /// The system ringer gave up: local dismiss if it still rings here.
  /// Late / unknown timeouts (plugin leftovers) are ignored.
  static void onNativeTimeout(String callId) {
    if (CallDedup.instance.isEnded(callId)) return;
    IncomingFlow.clearNativeRinging(callId);
    final s = _calls.value;
    if (s.isSameCall(callId) && s.phase == CallPhase.ringing) {
      EndFlow.dismissRinging(callId);
    }
  }

  static void onAudioSessionActivated() =>
      HeadlessJoin.instance.onAudioSessionActivated();

  /// iOS unlock: a video call answered on the lock screen gets its camera
  /// (E-48). The camera only works in front: with the app still behind,
  /// [onAppResumed] does it (I5).
  static Future<void> onDeviceUnlocked() async {
    final s = _calls.value;
    if (!s.isVideo || !s.phase.isLive) return;
    if (CallDevice.isForeground) await CallEngine.instance.repairVideo();
  }

  /// App in front: a call answered from the system UI goes to `/call`
  /// (never gated by "same call", E-22); a call still ringing on the system
  /// UI gets the in-app screen; the camera is claimed for video.
  static Future<void> onAppResumed() async {
    CallRuntime.ensureStarted();
    CallNavigator.flush();
    final s = _calls.value;
    if (s.phase.isLive) {
      if (_routeOnResume == s.callId && !CallNavigator.onCallRoute) {
        CallNavigator.toCall();
      }
      _routeOnResume = null;
      unawaited(CallEngine.instance.ensureVideoIfNeeded());
      if (s.isReceiver) unawaited(IncomingFlow.ensureMediaAccess(s));
    } else if (s.isReceiver &&
        s.phase == CallPhase.ringing &&
        !CallNavigator.onCallRoute) {
      CallNavigator.toIncoming();
    }
    unawaited(CallRequests.flushPendingDeclines());
  }

  // ── cold start (push-native calls these at boot) ──────────────────────

  /// An accept the native side kept (iOS snapshot, plugin `activeCalls`
  /// accepted, or [CallStore]). Not routed when older than
  /// [CallTimings.coldStartTtl] or closed on the server (E-16, E-85).
  static Future<void> onColdStartAccept(
    Map<String, dynamic> raw, {
    bool apiDone = true,
  }) async {
    final payload = CallPayload.parse(raw, selfId: CallIdentity.userId);
    if (payload == null || !payload.hasJoinCreds) return;
    if (payload.isStale(CallTimings.coldStartTtl) ||
        await _closedOnServer(payload.callId)) {
      CallDedup.instance.markEnded(payload.callId);
      EndFlow.endNativeOnce(payload.callId);
      return;
    }
    await onNativeAccepted(raw, apiDone: apiDone);
  }

  /// A call still ringing on the system UI at boot: adopt it (store +
  /// ringing ack); the in-app screen only when the app is in front.
  static Future<void> onColdStartRinging(Map<String, dynamic> raw) async {
    final payload = CallPayload.parse(raw, selfId: CallIdentity.userId);
    if (payload == null) return;
    if (await _closedOnServer(payload.callId)) {
      CallDedup.instance.markEnded(payload.callId);
      EndFlow.endNativeOnce(payload.callId);
      return;
    }
    await PushFlow.onInvite(
      raw,
      foreground: false,
      source: CallPushSource.launch,
    );
    if (CallDevice.isForeground &&
        _calls.value.isSameCall(payload.callId) &&
        _calls.value.phase == CallPhase.ringing) {
      CallNavigator.toIncoming();
    }
  }

  /// Boot: the stored pending accept (Android background isolate), the
  /// parked navigation, the decline replay queue.
  static Future<void> reconcile() async {
    CallRuntime.ensureStarted();
    try {
      final pending = await CallStore.takePendingAccept();
      if (pending != null) {
        await onColdStartAccept(pending.payload, apiDone: pending.apiDone);
      }
    } catch (e) {
      Log.w('NativeFlow', 'reconcile: $e');
    }
    CallNavigator.flush();
    unawaited(CallRequests.flushPendingDeclines());
  }

  /// RN's 2 s optimistic race: an error or no answer counts as open.
  static Future<bool> _closedOnServer(String callId) =>
      isCallClosedOnServer(callId, timeout: CallTimings.statusCheckTimeout);

  @visibleForTesting
  static void debugReset() {
    _routeOnResume = null;
    updateRetryDelays = CallTimings.updateRetry;
  }
}
