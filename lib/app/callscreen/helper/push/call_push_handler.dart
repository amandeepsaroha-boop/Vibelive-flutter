import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_queries.dart';
import '../call_signals.dart';
import '../native/call_isolate_bridge.dart';
import '../native/callkit_service.dart';
import '../native/native_call_marks.dart';
import '../state/call_dedup.dart';
import 'call_push_classifier.dart';
import 'push_envelope.dart';
import 'push_session.dart';

/// Routes one classified call push to the call logic ([CallSignals], raw
/// maps). The push layer only does what no one else can: the Android
/// ringer, its dismissal, and the hop from a background isolate to the UI
/// isolate. Normalisation, per-call dedup, TTLs, presentation and APIs are
/// the logic's. Never throws.
abstract final class CallPushHandler {
  static const _tag = 'CallPushHandler';

  /// A VoIP invite delayed longer than this is not rung (clock-skew safe;
  /// native iOS uses the same bound, the logic applies 45 s itself).
  static const maxRingAge = Duration(minutes: 2);

  /// The Android ringer rings for what is left of 45 s (RN TTL), at least
  /// [minRing]: the backend's CALL_ENDED stops it earlier.
  static const ringTtl = Duration(seconds: 45);
  static const minRing = Duration(seconds: 10);

  /// A timestamp further from "now" than this is a broken clock or unit,
  /// not a delay: the age is unknown, and an unknown age never blocks a ring.
  static const absurdSkew = Duration(days: 30);

  static final _recentPings = <String, DateTime>{};

  // Seams (tests run on the host, where nothing is Android and no plugin or
  // API exists).
  @visibleForTesting
  static bool Function() isAndroid = _isAndroid;
  @visibleForTesting
  static Future<bool> Function(PushEnvelope m, String callId, DateTime now)
  ringer = _ring;
  @visibleForTesting
  static Future<bool> Function({
    required String callId,
    required String receiverId,
  })
  sendRingingAck = CallRequests.sendRingingAck;
  @visibleForTesting
  static Future<void> Function(
    Map<String, dynamic> data, {
    required bool foreground,
    CallPushSource source,
  })
  onInvite = CallSignals.onInvite;

  static bool _isAndroid() => Platform.isAndroid;
  static Future<bool> _ring(PushEnvelope m, String callId, DateTime now) =>
      ringAndroid(m, callId, now: now);

  /// [foreground]: the app is on screen (in-app UI possible). [background]:
  /// this runs in an Android / iOS background isolate (no UI state here).
  static Future<void> handle(
    PushEnvelope m, {
    required CallPushSource source,
    required bool foreground,
    bool background = false,
    DateTime? now,
  }) async {
    try {
      await _handle(m, source, foreground, background, now ?? DateTime.now());
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }

  static Future<void> _handle(
    PushEnvelope m,
    CallPushSource source,
    bool foreground,
    bool background,
    DateTime now,
  ) async {
    final kind = CallPushClassifier.classify(m);
    final callId = m.callId;
    Log.d(
      _tag,
      '${kind.name} callId=$callId src=${source.name} fg=$foreground',
    );
    switch (kind) {
      case CallPushKind.invite:
        if (callId != null) {
          await _invite(m, callId, source, foreground, background, now);
        }
      case CallPushKind.ended:
        if (callId == null) return;
        await NativeCallMarks.markEnded(callId);
        await _dismissAndroidRinger(callId);
        if (background) {
          CallIsolateBridge.notifyUi(CallIsolateBridge.kindEnded, callId);
        }
        final status = m.status;
        await CallSignals.onEnded(
          callId,
          status: status.isEmpty ? null : status,
        );
      case CallPushKind.answeredElsewhere:
        if (callId == null) return;
        await _dismissAndroidRinger(callId);
        if (background) {
          CallIsolateBridge.notifyUi(
            CallIsolateBridge.kindAnsweredElsewhere,
            callId,
          );
        }
        CallSignals.onAnsweredElsewhere(callId);
      case CallPushKind.remoteRinging:
        // RN ignored the legacy one: the backend sends it before the
        // receiver's device truly rings.
        if (callId == null || m.type == 'call_ringing_legacy') return;
        CallSignals.onRemoteRinging(callId);
      case CallPushKind.ongoing:
        if (callId != null) CallSignals.onOngoingSignal(callId, m.raw);
      case CallPushKind.pingClient:
        // In the background the OS draws the FCM notification; its tap
        // routes the request (NotificationTapRouter).
        if (!foreground || background || _isRecentPing(m, now)) return;
        CallSignals.onCallbackRequest(m.raw);
      case CallPushKind.instantCallHostChanged:
        if (!background) CallSignals.onInstantCallHostChanged(m.raw);
      case CallPushKind.instantCallConnected:
        if (!background) CallSignals.onInstantCallConnected(m.raw);
      case CallPushKind.instantCallFailed:
        if (!background) CallSignals.onInstantCallFailed(m.raw);
      case CallPushKind.other:
        // A hint (decision 8): the logic toasts once; teardown still comes
        // from CALL_ENDED. Nothing to do without the UI isolate's call.
        if (m.type == 'low_balance_warning' && callId != null && !background) {
          CallSignals.onLowBalanceWarning(callId);
        }
      case CallPushKind.missedHistory:
        return;
    }
  }

  static Future<void> _invite(
    PushEnvelope m,
    String callId,
    CallPushSource source,
    bool foreground,
    bool background,
    DateTime now,
  ) async {
    // RN `claimIncomingCallPush`: an invite with a notification block is
    // never rung here, the OS would draw a duplicate (E39).
    if (source == CallPushSource.fcm && m.hasNotification) {
      Log.w(_tag, 'invite $callId carries a notification block: not rung');
      return;
    }
    if (background) {
      // A background isolate (FCM, app killed or in the background) has no
      // UI and never sees the accept: its CallController must stay idle, or
      // its 60 s ring timer ends the accepted plugin call (and with it the
      // foreground service and Telecom). Android rings with the plugin and
      // acks once; the UI isolate adopts the ring when it opens.
      if (!isAndroid()) return; // iOS: VoIP + CallKit own ringing
      if (!await ringer(m, callId, now)) return;
      await ackFromBackground(m, callId);
      return;
    }
    if (isAndroid() && !foreground) {
      // UI isolate, app not in front: the system ringer is ours on Android.
      if (!await ringer(m, callId, now)) return;
      await onInvite(m.raw, foreground: false, source: source);
      return;
    }
    // iOS never rings from Dart (native reported CallKit, decision 15);
    // in front: the logic shows the in-app screen.
    await onInvite(m.raw, foreground: foreground, source: source);
  }

  /// The ringing ack for a ring the background isolate showed, once per
  /// call across isolates (a durable mark, read by [adoptBackgroundAck]).
  @visibleForTesting
  static Future<void> ackFromBackground(PushEnvelope m, String callId) async {
    if (await NativeCallMarks.wasAcked(callId)) return;
    final receiverId =
        _str(m.data['receiverId']) ??
        _str(m.data['receiver_id']) ??
        PushSession.userId;
    if (receiverId == null) return;
    // Marked first: the UI isolate may adopt the ring while this is in
    // flight. A failed ack is only logged (RN), never retried from here.
    await NativeCallMarks.markAcked(callId);
    await sendRingingAck(callId: callId, receiverId: receiverId);
  }

  /// UI isolate, before handing a ring the background isolate showed to the
  /// logic (notification tap, cold start, launcher resume): its ringing ack
  /// was already sent, so the logic's once-per-call ack skips it.
  static Future<void> adoptBackgroundAck(String callId) async {
    try {
      if (callId.isEmpty || !await NativeCallMarks.wasAcked(callId)) return;
      if (CallDedup.instance.beginAck(callId)) {
        CallDedup.instance.finishAck(callId, ok: true);
      }
    } catch (_) {}
  }

  static String? _str(String? v) {
    final s = v?.trim() ?? '';
    return s.isEmpty || s == 'null' ? null : s;
  }

  /// Android: shows the `flutter_callkit_incoming` ringer for [m] unless it
  /// is not ours to ring. True when shown.
  static Future<bool> ringAndroid(
    PushEnvelope m,
    String callId, {
    DateTime? now,
  }) async {
    final why = await ringRejection(m, callId, now: now);
    if (why != null) {
      Log.d(_tag, 'not ringing $callId: $why');
      return false;
    }
    await NativeCallMarks.markRung(callId);
    await NativeCallMarks.saveInvite(callId, m.raw);
    final age = ageOf(m.sentAt, now ?? DateTime.now()) ?? Duration.zero;
    final left = ringTtl - age;
    return CallKitService.showIncoming(
      m.raw,
      callId: callId,
      ring: left < minRing ? minRing : (left > ringTtl ? ringTtl : left),
    );
  }

  /// Why [m] must not ring (null = ring it).
  static Future<String?> ringRejection(
    PushEnvelope m,
    String callId, {
    DateTime? now,
  }) async {
    if (!PushSession.isSignedIn) return 'signed out';
    if (!CallPushClassifier.isJoinable(m.data)) return 'no join credentials';
    final me = PushSession.userId;
    if (me != null && (m.data['callerId'] ?? m.data['caller_id']) == me) {
      return 'own call';
    }
    final age = ageOf(m.sentAt, now ?? DateTime.now());
    if (age != null && age > maxRingAge) return 'stale';
    if (await NativeCallMarks.isEnded(callId)) return 'already ended';
    if (await NativeCallMarks.wasRung(callId)) return 'already rung';
    return null;
  }

  /// Ends the Android ringer for [callId] when it is still RINGING. An
  /// answered call keeps its ongoing service: the logic ends it (an ongoing
  /// call is torn down by Agora, E-47), and answered-elsewhere never ends
  /// the device that answered.
  static Future<void> _dismissAndroidRinger(String callId) async {
    if (!Platform.isAndroid) return;
    final ringing = (await CallKitService.activeCalls()).any(
      (c) => c.callId == callId && !c.isAccepted,
    );
    if (!ringing) return;
    await NativeCallMarks.markAppEnded(callId);
    await CallKitService.end(callId);
  }

  /// How old a push sent at [sent] is, or null when that is unknown: no
  /// timestamp, a timestamp in the future (the device clock is behind), or
  /// one further than [absurdSkew] in the past (a broken clock or unit).
  /// An unknown age is never "stale": clock skew must not block a call.
  static Duration? ageOf(DateTime? sent, DateTime now) {
    if (sent == null) return null;
    final age = now.difference(sent);
    if (age.isNegative || age > absurdSkew) return null;
    return age;
  }

  /// FCM + VoIP copies of one PING_CLIENT: one callback sheet.
  static bool _isRecentPing(PushEnvelope m, DateTime now) {
    final key =
        m.data['expertDocId'] ?? m.data['expertId'] ?? m.data['uuid'] ?? '';
    _recentPings.removeWhere((_, at) => now.difference(at).inSeconds > 30);
    final last = _recentPings[key];
    _recentPings[key] = now;
    return last != null && now.difference(last).inSeconds < 10;
  }
}
