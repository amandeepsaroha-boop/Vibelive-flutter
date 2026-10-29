import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/query/query_client.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_api.dart';
import '../../../api/callscreen/call_errors.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/call_queries.dart';
import '../../../api/callscreen/pending_decline_queue.dart';
import '../../../api/listingflow/listing_models.dart';
import '../../../api/listingflow/listing_queries.dart';
import '../../../api/paymentscreen/payment_keys.dart';
import '../../../authscreen/helper/deep_links.dart';
import '../call_analytics.dart';
import '../call_controller.dart';
import '../call_identity.dart';
import '../call_navigator.dart';
import '../call_platform.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../engine/call_engine.dart';
import '../engine/headless_join.dart';
import '../state/call_constants.dart';
import '../state/call_dedup.dart';
import 'incoming_flow.dart';
import 'instant_call_flow.dart';

/// Every way a call ends, and leaving the call screens (RN `handleHangup`,
/// `exitToTabs`; decisions 1, 5, 9).
abstract final class EndFlow {
  static String? _ending;
  static String? _exitedFor;
  static final _nativeEnded = <String>{};

  static CallController get _calls => CallController.instance;

  /// A new call took the slot: its exit and hang-up guards start fresh.
  static void newCall() {
    _exitedFor = null;
    _ending = null;
  }

  /// The system call UI for [callId] goes, once (hang-up and the ended
  /// phase both ask; mem #10).
  static void endNativeOnce(String callId) {
    if (!_nativeEnded.add(callId)) return;
    if (_nativeEnded.length > 50) _nativeEnded.remove(_nativeEnded.first);
    try {
      unawaited(
        CallPlatform.instance.endNativeCall(callId).catchError((Object _) {}),
      );
    } catch (_) {}
  }

  /// Hang up (button, remote quit, timers, safety actions). Idempotent.
  /// The screen flips to ended at once; Callend runs in the background.
  /// [reason]: why, for analytics ([CallEndReason]).
  static Future<void> hangup({
    String reason = CallEndReason.userHangup,
  }) async {
    CallRuntime.ensureStarted();
    var s = _calls.value;
    final callId = s.callId;
    if (callId == null || !s.phase.isActive || _ending == callId) return;
    CallAnalytics.reason(callId, reason);
    _ending = callId;
    // The remote joined but the 500 ms connect delay (RN C8) has not run:
    // the call did connect. Stamp it, so the summary, the rating sheet and
    // the `completed` Callend agree (U13). Only the timestamp: going
    // through `ongoing` would start the connect side effects (Android
    // ongoing service, billing) that the end below undoes at once.
    if (CallEngine.instance.hasRemote && s.connectedAt == null) {
      final at = clock.now();
      _calls.update((c) => c.copyWith(connectedAt: at));
      s = _calls.value;
    }
    final now = DateTime.now();
    // RN `wasOngoing`: connected, or the remote is already in the channel.
    final connected = s.everConnected || CallEngine.instance.hasRemote;
    final input = endInput(
      s,
      connected: connected,
      seconds: connected ? math.max(1, s.durationSeconds(now)) : 0,
      at: now,
    );
    // Callend is dispatched before the ended phase starts the Agora leave
    // (A3); nothing here awaits before the native UI is cleared (mem #10).
    final sent = _afterHangup(input);
    _lastEnd = sent;
    _calls.end();
    endNativeOnce(callId);
    CallDedup.instance.markEnded(callId);
    unawaited(sent);
  }

  /// The Callend of the last hang-up (sign-out waits for it).
  static Future<void>? _lastEnd;

  /// Callend goes out FIRST, in parallel with the ring stop and the Agora
  /// leave: the server bills up to when it hears of the end (A3). A
  /// failure other than "already ended" is queued for replay (the
  /// idempotency key makes a replay safe).
  static Future<void> _afterHangup(CallEndInput input) async {
    final request = sendEnd(input);
    try {
      await CallRingtone.silence();
      await HeadlessJoin.instance.leave();
    } catch (_) {}
    await request;
    unawaited(InstantCallFlow.cancel());
    queryCache.invalidateAll(PaymentKeys.walletData);
  }

  /// `/call/Callend`; never throws. Lost races are fine, other failures
  /// go to the replay queue.
  static Future<void> sendEnd(CallEndInput input) async {
    try {
      await CallRequests.endCall(input);
    } on ApiException catch (e) {
      // Lost the race against the other side's end: nothing to do.
      if (e.isCallAlreadyEnded || e.isBenignDecline) return;
      Log.w('EndFlow', 'Callend failed, queued: $e');
      await _queue(input);
    } catch (e) {
      Log.w('EndFlow', 'Callend failed, queued: $e');
      await _queue(input);
    }
  }

  static Future<void> _queue(CallEndInput input) async {
    try {
      await PendingDeclineQueue.enqueue(input);
    } catch (e) {
      Log.w('EndFlow', 'queue Callend: $e');
    }
  }

  /// Sign-out (U3): whatever call exists ends now, while the token is
  /// still there. A ring is declined, a call is hung up (Agora left,
  /// wakelock released by the phase change); this waits for the request,
  /// at most [CallTimings.signOutEndWait], then clears the call.
  static Future<void> endForSignOut() async {
    CallRuntime.ensureStarted();
    final s = _calls.value;
    final callId = s.callId;
    if (callId == null) return;
    Future<void>? request;
    CallAnalytics.reason(callId, CallEndReason.signOut);
    if (s.isReceiver && s.phase == CallPhase.ringing) {
      request = IncomingFlow.declineCall(s);
    } else if (s.phase.isActive) {
      await hangup(reason: CallEndReason.signOut);
      request = _lastEnd;
    }
    try {
      await request?.timeout(CallTimings.signOutEndWait);
    } catch (_) {}
    try {
      await HeadlessJoin.instance.leave();
    } catch (_) {}
    if (_calls.value.phase != CallPhase.idle) _calls.reset();
  }

  /// The Callend body (decision 9): connected → `completed` with the
  /// wall-clock duration; a caller cancel → no status (E-92); a receiver
  /// that never connected → `declined`. `endedById` always set.
  static CallEndInput endInput(
    CallSession s, {
    required bool connected,
    required int seconds,
    DateTime? at,
  }) {
    final callId = s.callId ?? '';
    final endedBy = CallIdentity.endedBy(s);
    final type = s.isVideo ? CallType.video : CallType.voice;
    if (connected) {
      return CallEndInput(
        callId: callId,
        endedById: endedBy,
        startTime: s.connectedAt,
        endTime: at,
        durationSeconds: seconds,
        type: type,
        callerDocumentId: s.callerDocId,
      );
    }
    if (s.isCaller) {
      return CallEndInput.cancel(
        callId: callId,
        endedById: endedBy,
        type: type,
        callerDocumentId: s.callerDocId,
      );
    }
    return CallEndInput.decline(
      callId: callId,
      endedById: endedBy,
      type: type,
      callerDocumentId: s.callerDocId,
      at: at,
    );
  }

  /// Ended elsewhere (end push, native UI, server): the ended phase without
  /// any API call.
  static void endLocally(
    String callId, {
    String reason = CallEndReason.remoteEnded,
  }) {
    final s = _calls.value;
    if (!s.isSameCall(callId) || !s.phase.isActive) return;
    CallAnalytics.reason(s.callId ?? callId, reason);
    _ending = callId;
    _calls.end();
    endNativeOnce(callId);
    CallDedup.instance.markEnded(callId);
  }

  /// A receiver's ring goes away without a summary or an API call (caller
  /// cancelled, answered elsewhere, ring timeout).
  static void dismissRinging(
    String callId, {
    String reason = CallEndReason.callerCancelled,
  }) {
    final s = _calls.value;
    if (!s.isSameCall(callId) || s.phase != CallPhase.ringing) return;
    CallAnalytics.reason(s.callId ?? callId, reason);
    CallDedup.instance
      ..markEnded(callId)
      ..releaseClaims(callId);
    endNativeOnce(callId);
    _calls.reset();
  }

  /// RN C13: the channel could not be joined. A caller still cancels (the
  /// other phone would ring on); a receiver ends locally, like RN (E-56).
  static Future<void> joinFailed() async {
    final s = _calls.value;
    final callId = s.callId;
    if (callId == null || !s.phase.isActive) return;
    CallAnalytics.reason(callId, CallEndReason.joinFailed);
    if (s.isCaller && !s.everConnected) {
      return hangup(reason: CallEndReason.joinFailed);
    }
    endLocally(callId, reason: CallEndReason.joinFailed);
  }

  /// Leave the call screens for Home, once per call (decision 5): the
  /// caller lands on Discover with the host's profile re-opened, the
  /// receiver just on Home. A live call is minimized instead. [callId]:
  /// the call the asking screen showed; a stale screen (another call took
  /// the slot since) changes nothing.
  static void exitToHome({String? callId}) {
    final s = _calls.value;
    if (callId != null && s.callId != null && !s.isSameCall(callId)) return;
    // A new ring took the slot while the old screen was closing: show it.
    if (s.isReceiver && s.phase == CallPhase.ringing) {
      return CallNavigator.toIncoming();
    }
    if (s.phase.isActive) return minimize();
    final key = s.callId ?? callId ?? '';
    if (_exitedFor == key) return;
    _exitedFor = key;
    final caller = s.isCaller || (s.callId == null && _lastIsCaller(callId));
    final last = s.callId != null ? s : CallRuntime.lastCall;
    CallNavigator.toHome(tab: caller ? CallNavigator.discoverTab : null);
    // Android: a call that started on the lock screen goes back there.
    if (last.openedLocked) unawaited(CallPlatform.instance.minimizeApp());
    if (s.phase == CallPhase.ended) _calls.reset();
    if (caller) unawaited(_reopenHost(last));
  }

  static bool _lastIsCaller(String? callId) {
    final last = CallRuntime.lastCall;
    return last.isCaller && (callId == null || last.isSameCall(callId));
  }

  /// Discover re-opens the host's profile: their USER documentId. The
  /// session's `receiverDocId` is the expert-profile documentId, so it is
  /// only used to look the user up when the call never knew it.
  static Future<void> _reopenHost(CallSession s) async {
    var userDoc = s.remote.documentId;
    if (userDoc == null || userDoc.isEmpty) {
      try {
        final host = await hostLookup(
          expertDocumentId: s.receiverDocId,
          userId: s.remote.id ?? s.receiverId,
        );
        userDoc = host.userDocumentId;
      } catch (e) {
        Log.w('EndFlow', 'host lookup: $e');
      }
    }
    final id = userDoc;
    if (id == null || id.isEmpty) return;
    Timer(CallTimings.reopenProfileDelay, () {
      try {
        DeepLinks.instance.setOpenUser(id);
      } catch (_) {}
    });
  }

  /// Seam: the host by expert-profile documentId / user id (tests).
  @visibleForTesting
  static Future<HostCard> Function({String? expertDocumentId, String? userId})
  hostLookup = ensureCallbackHost;

  /// Header back during a call (decision 1): Home, the call keeps running.
  static void minimize() {
    if (!_calls.value.phase.isActive) return exitToHome();
    CallNavigator.toHome();
  }

  /// The "return to call" bar.
  static void returnToCall() {
    final s = _calls.value;
    if (!s.phase.isActive) return;
    if (s.isReceiver && s.phase == CallPhase.ringing) {
      return CallNavigator.toIncoming();
    }
    CallNavigator.toCall();
    unawaited(CallEngine.instance.ensureVideoIfNeeded());
  }

  @visibleForTesting
  static void debugReset() {
    _ending = null;
    _exitedFor = null;
    _lastEnd = null;
    hostLookup = ensureCallbackHost;
    _nativeEnded.clear();
  }
}
