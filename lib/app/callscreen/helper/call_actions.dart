import 'package:flutter/widgets.dart';

import '../../api/listingflow/listing_models.dart';
import '../../../core/utils/log.dart';
import 'call_analytics.dart';
import 'call_controller.dart';
import 'call_runtime.dart';
import 'call_session.dart';
import 'flows/end_flow.dart';
import 'flows/incoming_flow.dart';
import 'flows/instant_call_flow.dart';
import 'flows/outgoing_flow.dart';
import 'flows/safety_flow.dart';

/// Who to call when there is no [HostCard] (callback sheet, history redial).
@immutable
class CallTarget {
  const CallTarget({
    required this.receiverId,
    this.receiverDocId,
    this.name,
    this.avatarUrl,
    this.isCompany = false,
    this.categoryId,
    this.ratePerMin,
  });

  /// Numeric public-user id of the person called.
  final String receiverId;
  final String? receiverDocId;
  final String? name;
  final String? avatarUrl;
  final bool isCompany;

  /// RN `categoryId` (history redial: the old call's category).
  final String? categoryId;

  /// The host's per-minute rate for the call type being placed (voice or
  /// video), when the caller already knows it (callback sheet). Drives the
  /// max-duration cap; null = looked up from the host's profile.
  final num? ratePerMin;
}

/// Result of a report / block run from a call screen (RN "Thanks for
/// telling us" copy picks one of these).
enum CallSafetyOutcome { done, noTarget, failed }

/// What the call screen shows once the call ended (RN
/// `handleCallEndFeedbackTransition`).
enum PostCallStep {
  /// Caller after a connected call: rating sheet after 300 ms.
  feedback,

  /// Everyone else: keep the summary 1.2 s, then [CallActions.exitToHome].
  exit,
}

/// Everything a user does on the call screens. CONTRACT between the call UI
/// (calls these) and the call logic (implements them). Never throw: failures
/// surface as alerts / toasts inside, the way RN did.
abstract final class CallActions {
  /// Profile → call (RN `handleInitiateCall`): the profile already ran its
  /// checks and the safety prompt. Mic (+camera) permission gate,
  /// `/initiateCall`, busy / invalid / failure alerts, then the call screen.
  static Future<void> placeCall(
    BuildContext context, {
    required HostCard host,
    required bool video,
  }) => _guard<void>(
    () => OutgoingFlow.place(OutgoingRequest.fromHost(host, video: video)),
  );

  /// Same without a host card (callback sheet, history redial; RN
  /// `initiateCallTo`: no balance gate, no safety prompt).
  static Future<void> placeCallTo(
    BuildContext context, {
    required CallTarget target,
    required bool video,
  }) => _guard<void>(
    () => OutgoingFlow.place(OutgoingRequest.fromTarget(target, video: video)),
  );

  /// Incoming: Accept (ringtone off BEFORE anything awaits, mem #2).
  static Future<void> accept() => _guard(IncomingFlow.accept);

  /// Incoming: Decline (local teardown first, API after, 120 s ghost skip).
  static Future<void> decline() => _guard(IncomingFlow.decline);

  /// Incoming: decline, then block / report the caller (RN safety rows).
  /// True when the block / report request succeeded. [call]: the session
  /// captured BEFORE the confirm dialog (`CallController.instance.value`):
  /// the ring may end while the dialog is up; the decline is then skipped
  /// but the block / report still goes to that caller.
  static Future<bool> declineAndBlock({CallSession? call}) =>
      _guard(() => IncomingFlow.declineAndBlock(call: call), false);
  static Future<bool> declineAndReport({CallSession? call}) =>
      _guard(() => IncomingFlow.declineAndReport(call: call), false);

  /// Instant call: one tap, system finds a host. Permission gate,
  /// `/instant-call/initiate`, then the call screen with cascading ring.
  static Future<void> talkNow({bool video = false}) =>
      _guard<void>(() => InstantCallFlow.place(video: video));

  /// Call screen hang-up (idempotent; Callend in the background).
  /// [reason]: why, for analytics ([CallEndReason]).
  static Future<void> hangup({String reason = CallEndReason.userHangup}) =>
      _guard(() => EndFlow.hangup(reason: reason));

  /// Sign-out while a call exists: decline a ring / hang up a call, leave
  /// Agora, release the wakelock, and wait (bounded) until the Callend
  /// request went out, so it still carries the session token. Call it
  /// BEFORE the token is dropped. No-op when there is no call.
  static Future<void> endForSignOut() => _guard(EndFlow.endForSignOut);

  /// In-call "Something wrong?" panel: report / block, then hang up. The
  /// screen shows the "Thanks for telling us" alert for the outcome (copy:
  /// `CallFlowKeys.safetyMessage`).
  static Future<CallSafetyOutcome> reportDuringCall() =>
      _guard(SafetyFlow.reportDuringCall, CallSafetyOutcome.failed);
  static Future<CallSafetyOutcome> blockDuringCall() =>
      _guard(SafetyFlow.blockDuringCall, CallSafetyOutcome.failed);

  /// Rules for the ended screen (caller + connected → feedback).
  static PostCallStep afterEnded() {
    final now = CallController.instance.value;
    final s = now.callId != null ? now : CallRuntime.lastCall;
    return s.isCaller && s.everConnected
        ? PostCallStep.feedback
        : PostCallStep.exit;
  }

  /// Rating sheet submit (caller, connected call). Never throws. The sheet
  /// closes and calls [exitToHome] afterwards (RN always exited).
  static Future<void> submitFeedback({
    required int rating,
    String comments = '',
  }) => _guard(
    () => SafetyFlow.submitFeedback(rating: rating, comments: comments),
  );

  /// Rating sheet "Block this User". True on success; the sheet then calls
  /// [exitToHome] (decision 4).
  static Future<bool> blockAfterCall() =>
      _guard(SafetyFlow.blockAfterCall, false);

  /// Leave the call screens for Home (once): the caller lands on Discover
  /// with the host's profile re-opened; a receiver just on Home. Resets the
  /// call when it is over. [callId]: the call the screen was showing; a
  /// stale screen's exit is ignored once another call took the slot.
  static void exitToHome({String? callId}) =>
      _guardSync(() => EndFlow.exitToHome(callId: callId));

  /// Header back during a live call: Home, the call keeps running (a
  /// "return to call" bar brings it back). RN's back silently dropped it.
  static void minimize() => _guardSync(EndFlow.minimize);

  /// The "return to call" bar.
  static void returnToCall() => _guardSync(EndFlow.returnToCall);

  /// Nothing throws out of a user action. [fallback] must be given for a
  /// non-void [T].
  static Future<T> _guard<T>(Future<T> Function() body, [T? fallback]) async {
    try {
      return await body();
    } catch (e, st) {
      Log.e('CallActions', e, st);
      return fallback as T;
    }
  }

  static void _guardSync(void Function() body) {
    try {
      body();
    } catch (e, st) {
      Log.e('CallActions', e, st);
    }
  }
}
