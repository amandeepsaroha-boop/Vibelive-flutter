import 'package:flutter/foundation.dart';

import '../../../core/utils/log.dart';
import 'call_billing.dart';
import 'call_controller.dart';
import 'call_identity.dart';
import 'call_payload.dart';
import 'flows/native_flow.dart';
import 'flows/push_flow.dart';
import 'state/call_store.dart';

/// Where a call push came from.
enum CallPushSource { fcm, voip, notificationTap, launch }

/// An expert's "call me back" nudge (PING_CLIENT), for the callback sheet.
@immutable
class CallbackRequest {
  const CallbackRequest(this.data);

  /// Raw push data (`expertId`, `expertDocId`, `expertName`, `expertPic` /
  /// `ProfilePic`, `categoryName`, optional prices).
  final Map<String, dynamic> data;
}

/// Everything the push / native layer tells the call logic. CONTRACT:
/// the push + native layer CALLS these with raw push / plugin data; the call
/// logic IMPLEMENTS them (payload normalisation, dedup, TTLs, guards,
/// navigation, Agora). Never throw.
abstract final class CallSignals {
  /// A ring (classified as an invite, join creds present). [foreground]:
  /// the app is active → in-app incoming screen + ringtone; otherwise the
  /// system ringer is already up (iOS CallKit by native code, Android by the
  /// push layer) and only the store + ringing ack are needed.
  static Future<void> onInvite(
    Map<String, dynamic> data, {
    required bool foreground,
    CallPushSource source = CallPushSource.fcm,
  }) => _guard(
    () => PushFlow.onInvite(data, foreground: foreground, source: source),
  );

  /// Caller side: the receiver's phone rings (`CALL_RINGING`).
  static void onRemoteRinging(String callId) =>
      _guardSync(() => PushFlow.onRemoteRinging(callId));

  /// Caller side: accepted / CallTimer / connected signal for our call.
  /// Receiver side: confirmation only (never rings, never tears down).
  static void onOngoingSignal(String callId, Map<String, dynamic> data) =>
      _guardSync(() => PushFlow.onOngoingSignal(callId, data));

  /// `CALL_ENDED` / declined / missed / cancel for [callId] (any side).
  /// A ringing / calling / accepted call is torn down; an ongoing one is
  /// left to Agora's remote-quit (RN E-47), with a short grace after which
  /// a server-side end (low balance, admin) ends it locally (no API).
  static Future<void> onEnded(String callId, {String? status}) =>
      _guard(() => PushFlow.onEnded(callId, status: status));

  /// `CALL_ANSWERED_ELSEWHERE`: stop ringing here unless THIS device
  /// answered. No API.
  static void onAnsweredElsewhere(String callId) =>
      _guardSync(() => PushFlow.onAnsweredElsewhere(callId));

  /// `LOW_BALANCE_WARNING` for [callId] (a hint, decision 8): the
  /// low-balance toast once per call. Teardown still comes from
  /// `CALL_ENDED`.
  static void onLowBalanceWarning(String callId) =>
      _guardSync(() => CallBilling.warnOnce(callId));

  /// `PING_CLIENT` (foreground push or notification tap). Never shown to
  /// the expert who sent it (E-73), nor over a call.
  static void onCallbackRequest(Map<String, dynamic> data) => _guardSync(() {
    final flat = CallPayload.flatten(data);
    final expertId = CallPayload.read(flat, const ['expertId']);
    final self = CallIdentity.userId;
    if (self != null && expertId == self) return;
    if (CallController.instance.value.phase.isActive) return;
    _callbackRequest.value = CallbackRequest(flat);
  });

  /// The pending callback request for the UI to show (null = none).
  static ValueListenable<CallbackRequest?> get callbackRequest =>
      _callbackRequest;
  static final _callbackRequest = ValueNotifier<CallbackRequest?>(null);

  /// The UI showed / dismissed the callback sheet.
  static void clearCallbackRequest() => _callbackRequest.value = null;

  // ── Native CallKit / notification actions (already handled natively:
  // ── never send the API again from here, mem #15) ──────────────────────

  /// Answered from the system UI (CallKit / notification). Native already
  /// sent `UpdateCall ongoing` on iOS ([apiDone]). Fill the store as
  /// accepted (uid from receiverId, mem #11), join audio-only once the
  /// audio session is up, route to `/call` when the app is in front.
  static Future<void> onNativeAccepted(
    Map<String, dynamic> payload, {
    bool apiDone = false,
  }) => _guard(() => NativeFlow.onNativeAccepted(payload, apiDone: apiDone));

  /// Declined from the system UI. iOS native sent Callend; Android: the
  /// push layer sends it ([apiDone] false → the logic sends it, with the
  /// ring [payload] when the store never saw the call).
  static Future<void> onNativeDeclined(
    String callId, {
    bool apiDone = true,
    Map<String, dynamic>? payload,
  }) => _guard(
    () =>
        NativeFlow.onNativeDeclined(callId, apiDone: apiDone, payload: payload),
  );

  /// Ended an answered call from the system UI (native sent Callend
  /// completed on iOS). Leave Agora + reset; NO API.
  static Future<void> onNativeEnded(String callId) =>
      _guard(() => NativeFlow.onNativeEnded(callId));

  /// iOS: the native `/UpdateCall` sent at a CallKit answer failed (no
  /// network on wake, 5xx, timeout). The logic sends it again (with this
  /// device's `answeredDeviceId`, bounded retries); an `alreadyOngoing`
  /// reply is fine (E-86). Completes when it went through or gave up.
  static Future<void> onNativeUpdateFailed(String callId) =>
      _guard(() => NativeFlow.onNativeUpdateFailed(callId));

  /// The system ringer timed out.
  static void onNativeTimeout(String callId) =>
      _guardSync(() => NativeFlow.onNativeTimeout(callId));

  /// iOS CallKit activated the audio session (run a parked headless join).
  static void onAudioSessionActivated() =>
      _guardSync(NativeFlow.onAudioSessionActivated);

  /// iOS device unlocked (`protectedDataDidBecomeAvailable`): repair the
  /// camera of a call answered on the lock screen.
  static Future<void> onDeviceUnlocked() => _guard(NativeFlow.onDeviceUnlocked);

  /// App came to the foreground: a call answered from the system UI goes
  /// to `/call`, a system ring gets the in-app screen, video claims the
  /// camera, queued declines replay.
  static Future<void> onAppResumed() => _guard(NativeFlow.onAppResumed);

  // ── Cold start (push-native's boot reconcile) ──────────────────────────

  /// An accept kept by native code (iOS pending-accept snapshot, plugin
  /// `activeCalls()` with `isAccepted`). Skipped when older than 5 min or
  /// already closed on the server (2 s check, E-16 / E-85); else as
  /// [onNativeAccepted].
  static Future<void> onColdStartAccept(
    Map<String, dynamic> payload, {
    bool apiDone = true,
  }) => _guard(() => NativeFlow.onColdStartAccept(payload, apiDone: apiDone));

  /// A call still ringing on the system UI at boot: store + ringing ack,
  /// the in-app screen when the app is in front. Closed calls are dropped.
  static Future<void> onColdStartRinging(Map<String, dynamic> payload) =>
      _guard(() => NativeFlow.onColdStartRinging(payload));

  /// Another isolate (the Android background handler) saw a system-UI
  /// accept: keep it for [reconcile] in the UI isolate.
  static Future<void> savePendingAccept(
    Map<String, dynamic> payload, {
    bool apiDone = false,
  }) => _guard(() => CallStore.savePendingAccept(payload, apiDone: apiDone));

  /// Boot, after the router exists: the stored pending accept, the parked
  /// navigation and the decline replay queue.
  static Future<void> reconcile() => _guard(NativeFlow.reconcile);

  static Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (e, st) {
      Log.e('CallSignals', e, st);
    }
  }

  static void _guardSync(void Function() body) {
    try {
      body();
    } catch (e, st) {
      Log.e('CallSignals', e, st);
    }
  }
}
