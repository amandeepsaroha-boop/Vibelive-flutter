import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_api.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/call_queries.dart';
import '../call_controller.dart';
import '../call_device.dart';
import '../call_identity.dart';
import '../call_navigator.dart';
import '../call_permissions.dart';
import '../call_platform.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../call_timers.dart';
import '../engine/call_engine.dart';
import '../engine/headless_join.dart';
import '../state/call_constants.dart';
import '../state/call_dedup.dart';
import 'end_flow.dart';
import 'safety_flow.dart';

/// The receiver's choices on a ringing call (RN IncomingCallScreen
/// `handleAccept` / `handleDecline` / safety rows).
abstract final class IncomingFlow {
  static bool _acting = false;
  static final _nativeRinging = <String>{};

  static CallController get _calls => CallController.instance;

  /// A system ringer (CallKit / the Android call notification) is up for
  /// [callId]: an in-app Accept must answer it natively too.
  static void markNativeRinging(String callId) => _nativeRinging.add(callId);
  static void clearNativeRinging(String callId) =>
      _nativeRinging.remove(callId);

  /// [markNativeRinging] was called for [callId] (and it is not answered
  /// or over yet). Native uses it before promoting an in-app ring to
  /// CallKit.
  static bool isMarkedNativeRinging(String callId) =>
      _nativeRinging.contains(callId);

  /// Accept: the mic (+ camera) gate first (A2: denied keeps it ringing,
  /// nothing is billed or joined), then the phase flips BEFORE anything
  /// else awaits, then the ring stops (never touching the audio session),
  /// then `/UpdateCall` with this device's id, the join and `/call` (mem
  /// #2, E-20, E-21).
  static Future<void> accept() async {
    CallRuntime.ensureStarted();
    final s = _calls.value;
    final callId = s.callId;
    if (callId == null || !s.isReceiver || s.phase != CallPhase.ringing) {
      return;
    }
    if (_acting) return;
    _acting = true;
    try {
      if (!await CallPermissions.ensureForCall(video: s.isVideo)) return;
      // The ring may have ended (or been replaced) during the prompt.
      final ringing = _calls.value;
      if (!ringing.isSameCall(callId) || ringing.phase != CallPhase.ringing) {
        return;
      }
      _calls.setAccepted();
      _accessChecked.add(callId);
      CallDedup.instance
        ..markAnswered(callId)
        ..releaseClaims(callId);
      CallTimers.instance.cancel(CallTimers.incomingRing);
      await CallRingtone.silence();
      final native = _nativeRinging.remove(callId);
      if (native) {
        unawaited(CallPlatform.instance.answerNativeRinging(callId));
      }
      final accepted = _calls.value;
      if (native && CallDevice.isIOS) {
        // CallKit's answer action sends `/UpdateCall` natively (I6); a
        // failure there comes back as `CallSignals.onNativeUpdateFailed`.
        CallDedup.instance.beginUpdateCall(callId);
      } else {
        unawaited(reportOngoing(accepted, answering: true));
      }
      unawaited(noteLocked(callId));
      final uid = accepted.localUid;
      if (uid != null && accepted.isSameCall(callId)) {
        // A CallKit call answered from the app: CallKit activates the audio
        // session; joining first gives a silent call (CE).
        if (native && CallDevice.isIOS) {
          unawaited(
            HeadlessJoin.instance.joinWhenAudioReady(
              channel: accepted.channelName ?? '',
              token: accepted.token ?? '',
              uid: uid,
              video: accepted.isVideo,
            ),
          );
        } else {
          unawaited(
            CallEngine.instance.join(
              channel: accepted.channelName ?? '',
              token: accepted.token ?? '',
              uid: uid,
              video: accepted.isVideo,
            ),
          );
        }
      }
      CallNavigator.toCall();
      armPeerFallback(callId);
    } catch (e) {
      Log.w('IncomingFlow', 'accept: $e');
    } finally {
      _acting = false;
    }
  }

  /// Calls whose mic / camera access was settled (in-app accept, or the
  /// post-accept check below).
  static final _accessChecked = <String>{};

  /// A call answered from the system UI never passed the in-app gate (A2):
  /// once the app is in front, ask for what is missing (once per call); a
  /// grant restarts the local capture so the other side hears / sees us.
  static Future<void> ensureMediaAccess(CallSession s) async {
    final callId = s.callId;
    if (callId == null || !s.phase.isLive || !CallDevice.isForeground) return;
    if (!_accessChecked.add(callId)) return;
    if (_accessChecked.length > 20) _accessChecked.remove(_accessChecked.first);
    if (await CallPermissions.grantedAfterAsking(video: s.isVideo) &&
        _calls.value.isSameCall(callId)) {
      await CallEngine.instance.restartLocalMedia();
    }
  }

  /// A9: the device was locked when the call arrived / was answered: the
  /// call goes back to the lock screen afterwards (Android). Never throws.
  static Future<void> noteLocked(String callId) async {
    bool locked;
    try {
      locked = await CallPlatform.instance.isDeviceLocked();
    } catch (_) {
      return;
    }
    if (!locked) return;
    _calls.update(
      (c) => c.isSameCall(callId) && !c.openedLocked
          ? c.copyWith(openedLocked: true)
          : c,
    );
  }

  /// Answered but the other side never shows up in the channel: hang up
  /// after the remote-drop grace instead of "connecting" forever.
  static void armPeerFallback(String callId) {
    CallTimers.instance.arm(
      CallTimers.remoteDrop,
      CallTimings.remoteDropGrace,
      () {
        final now = _calls.value;
        if (now.isSameCall(callId) &&
            now.phase == CallPhase.accepted &&
            !CallEngine.instance.hasRemote) {
          unawaited(EndFlow.hangup());
        }
      },
    );
  }

  /// `/UpdateCall ongoing` once per call (E-86). [answering]: this device
  /// answered → `answeredDeviceId`, so the backend stops ringing only the
  /// receiver's other devices (E-76). Never throws.
  /// True when it reached the backend (or was already sent).
  static Future<bool> reportOngoing(
    CallSession s, {
    required bool answering,
  }) async {
    final callId = s.callId;
    if (callId == null) return false;
    if (!CallDedup.instance.beginUpdateCall(callId)) return true;
    try {
      final result = await CallRequests.updateStatus(
        CallStatusUpdate(
          callId: callId,
          callerId: s.callerId,
          receiverId: s.receiverId,
          type: s.isVideo ? CallType.video : CallType.voice,
          category: s.category,
          answeredDeviceId: answering ? await CallIdentity.deviceId() : null,
        ),
      );
      // Fine for the caller and the device that answered (E-86).
      if (result.alreadyOngoing) Log.d('IncomingFlow', 'already ongoing');
      return true;
    } on ApiException catch (e) {
      // A later delivery (deep link, resume, remote join) may retry.
      CallDedup.instance.failUpdateCall(callId);
      Log.w('IncomingFlow', 'UpdateCall failed: $e');
      return false;
    } catch (e) {
      CallDedup.instance.failUpdateCall(callId);
      return false;
    }
  }

  /// Decline: local teardown first (ended in memory, ring off, idle, Home),
  /// then the API in the background, skipped for a ghost ring older than
  /// [CallTimings.ghostDeclineTtl] (E-15); a failure is queued (E-27).
  static Future<void> decline() async {
    final declined = _declineNow();
    if (declined != null) unawaited(declined.api);
  }

  /// Declines [call] if it still rings here (sign-out). Completes when the
  /// decline request is done (or queued).
  static Future<void> declineCall(CallSession call) async {
    final id = call.callId;
    if (id == null) return;
    await _declineNow(onlyCallId: id, force: true)?.api;
  }

  /// Decline, then block the caller ("Blocked from an incoming call.").
  /// [call]: the ring as captured before the confirm (U2).
  static Future<bool> declineAndBlock({CallSession? call}) async {
    final s = _declineThenTarget(call);
    if (s == null) return false;
    return SafetyFlow.block(_callerKey(s), CallWire.blockedIncoming);
  }

  /// Decline, then report the caller ("Reported from an incoming call.").
  static Future<bool> declineAndReport({CallSession? call}) async {
    final s = _declineThenTarget(call);
    if (s == null) return false;
    return SafetyFlow.report(_callerKey(s), CallWire.reportedIncoming);
  }

  /// Declines the ring if it still rings (only [captured]'s call when
  /// given) and returns the call whose caller is blocked / reported: the
  /// declined one, else [captured], else the ring that just went away
  /// ([CallRuntime.lastCall]).
  static CallSession? _declineThenTarget(CallSession? captured) {
    final declined = _declineNow(onlyCallId: captured?.callId);
    if (declined != null) return declined.call;
    if (captured != null && captured.callId != null && captured.isReceiver) {
      return captured;
    }
    final last = CallRuntime.lastCall;
    return last.isReceiver && last.callId != null ? last : null;
  }

  static String? _callerKey(CallSession s) =>
      s.remote.documentId ?? s.callerDocId ?? s.remote.id;

  /// The declined call and its API request, or null when there was
  /// nothing to decline. [force]: even while an accept is in flight.
  static ({CallSession call, Future<void> api})? _declineNow({
    String? onlyCallId,
    bool force = false,
  }) {
    CallRuntime.ensureStarted();
    final s = _calls.value;
    final callId = s.callId;
    if (callId == null || !s.isReceiver || s.phase != CallPhase.ringing) {
      return null;
    }
    if (onlyCallId != null && !s.isSameCall(onlyCallId)) return null;
    if (_acting && !force) return null;
    _acting = true;
    try {
      CallDedup.instance
        ..markEnded(callId)
        ..releaseClaims(callId);
      unawaited(CallRingtone.silence());
      _nativeRinging.remove(callId);
      EndFlow.endNativeOnce(callId);
      _calls.reset();
      CallNavigator.toHome();
      final sent = s.sentAt;
      final ghost =
          sent != null &&
          DateTime.now().difference(sent) > CallTimings.ghostDeclineTtl;
      return (call: s, api: ghost ? Future<void>.value() : sendDecline(s));
    } finally {
      _acting = false;
    }
  }

  /// `Callend {status: declined, endedById: receiver}`; benign "already
  /// closed" answers are fine, other failures go to the replay queue.
  static Future<void> sendDecline(CallSession s) async {
    final callId = s.callId;
    if (callId == null) return;
    try {
      await CallRequests.declineOrQueue(
        CallEndInput.decline(
          callId: callId,
          endedById: CallIdentity.endedBy(s),
          type: s.isVideo ? CallType.video : CallType.voice,
          callerDocumentId: s.callerDocId,
        ),
      );
    } catch (e) {
      Log.w('IncomingFlow', 'decline: $e');
    }
  }

  @visibleForTesting
  static void debugReset() {
    _acting = false;
    _nativeRinging.clear();
    _accessChecked.clear();
  }
}
