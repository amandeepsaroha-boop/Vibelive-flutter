import 'dart:async';
import 'dart:io' show Platform;

import '../../../../core/session/session_store.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/pending_decline_queue.dart';
import '../call_actions.dart';
import '../call_analytics.dart';
import '../call_controller.dart';
import '../call_signals.dart';
import '../push/call_push_handler.dart';
import '../push/heartbeat_handler.dart';
import '../push/push_classifier.dart';
import '../push/push_envelope.dart';
import '../push/voip_token_registrar.dart';
import '../push/wallet_notifications.dart';
import 'callkit_service.dart';
import 'headless_call_end.dart';
import 'native_call_bridge.dart';
import 'native_call_marks.dart';

/// System call UI events (plugin + iOS bridge) → the call logic
/// ([CallSignals]), plus cold-start reconciliation and resume handling
/// (spec_call_native §2.7). UI isolate only.
///
/// Listeners attach synchronously at the top of `main()` ([attach]); events
/// are processed in order, once boot opened the gate ([open]), so nothing
/// fired during a VoIP launch is lost or handled before prefs and the
/// session exist.
abstract final class NativeCallEvents {
  static const _tag = 'NativeCallEvents';
  static bool _attached = false;
  static final _gate = Completer<void>();
  static Future<void> _chain = Future.value();

  /// Plugin ENDED + bridge `nativeEnded` for one CallKit end: one signal.
  static final _endedAt = <String, DateTime>{};

  /// First thing in `main()`: before anything awaits Agora, Firebase or the
  /// network.
  static void attach() {
    if (_attached) return;
    _attached = true;
    CallKitService.listen();
    CallKitService.signals.listen((s) => _enqueue(() => _onSignal(s)));
    NativeCallBridge.events().listen((e) => _enqueue(() => _onBridge(e)));
  }

  /// Boot is far enough along (prefs, session): handle queued events.
  static void open() {
    if (!_gate.isCompleted) _gate.complete();
  }

  /// In order, but never blocking: a handler may await something a LATER
  /// event releases (an accept's headless join waits for the audio-session
  /// event), so each one only holds the line for [_slot].
  static void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) => _gate.future).then((_) => _bounded(job));
  }

  static const _slot = Duration(milliseconds: 1500);

  static Future<void> _bounded(Future<void> Function() job) =>
      _guard(job).timeout(_slot, onTimeout: () {});

  // ── plugin events ──────────────────────────────────────────────────────

  static Future<void> _onSignal(CallKitSignal s) async {
    // iOS PushKit compliance throwaways are never calls (§2.9).
    if (s.isCompliance) return;
    Log.d(_tag, '${s.action.name} ${s.callId}');
    switch (s.action) {
      case CallKitAction.accepted:
        await _accepted(s.callId, s.extra);
      case CallKitAction.declined:
        await _declined(s.callId, s.extra);
      case CallKitAction.ended:
        await _ended(s.callId, s.extra);
      case CallKitAction.callback:
        // Some OEMs send the ongoing notification's Hang up as CALLBACK. A
        // missed-call "Call back" never shows (missed notification is off).
        if (CallController.instance.value.isSameCall(s.callId)) {
          await _ended(s.callId, s.extra);
        }
      case CallKitAction.timedOut:
        if (s.callId.isEmpty) return;
        if (!Platform.isIOS && await NativeCallMarks.isAppEnded(s.callId)) {
          return;
        }
        CallSignals.onNativeTimeout(s.callId);
      case CallKitAction.audioSession:
        if (s.flag) CallSignals.onAudioSessionActivated();
      case CallKitAction.voipTokenUpdated:
        await VoipTokenRegistrar.refresh();
      case CallKitAction.incoming:
      case CallKitAction.started:
      case CallKitAction.connected:
        // The push already told the logic; nothing new here.
        break;
    }
  }

  static Future<void> _accepted(
    String callId,
    Map<String, dynamic> extra,
  ) async {
    Log.w('CallAccept', 'plugin ACCEPT event $callId (UI isolate)');
    if (callId.isEmpty) return;
    if (Platform.isIOS) {
      // The live event delivered it: the cold-start snapshot must not replay.
      await NativeCallBridge.consumePendingAccept();
      await CallSignals.onNativeAccepted(extra, apiDone: true);
      return;
    }
    // Android: nothing native sent `/UpdateCall`.
    await CallSignals.onNativeAccepted(extra, apiDone: false);
  }

  static Future<void> _declined(
    String callId,
    Map<String, dynamic> extra,
  ) async {
    if (callId.isEmpty) return;
    if (Platform.isIOS) {
      // CXEndCallAction: native already sent Callend (mem #6).
      await CallSignals.onNativeDeclined(callId, apiDone: true, payload: extra);
      return;
    }
    // Android: the echo of the app's own endCall is not a decline (a
    // Callend there would bill a call another device answered).
    if (await NativeCallMarks.isAppEnded(callId)) return;
    await CallSignals.onNativeDeclined(callId, apiDone: false, payload: extra);
  }

  static Future<void> _ended(String callId, Map<String, dynamic> extra) async {
    if (callId.isEmpty || _recentlyEnded(callId)) return;
    if (Platform.isIOS) {
      // CallKit-UI end of an answered call: native sent Callend completed
      // (mem #15). Leave + reset only.
      await CallSignals.onNativeEnded(callId);
      return;
    }
    if (await NativeCallMarks.isAppEnded(callId)) return;
    // Android: the ongoing notification's "End Call" is a local hang-up WITH
    // the API (§3.6). The logic has no signal for that: when it holds the
    // call this is the user's hang-up; otherwise send it headless.
    final call = CallController.instance.value;
    if (call.isSameCall(callId) && call.phase.isActive) {
      await CallActions.hangup(reason: CallEndReason.systemUi);
    } else {
      await HeadlessCallEnd.hangUp(callId, extra);
      await CallSignals.onNativeEnded(callId);
    }
  }

  static bool _recentlyEnded(String callId) {
    final now = DateTime.now();
    _endedAt.removeWhere((_, at) => now.difference(at).inSeconds > 10);
    if (_endedAt.containsKey(callId)) return true;
    _endedAt[callId] = now;
    return false;
  }

  // ── iOS bridge events ──────────────────────────────────────────────────

  static Future<void> _onBridge(Map<String, dynamic> e) async {
    switch (e['event']) {
      case 'voipPush':
        final data = e['data'];
        if (data is! Map) return;
        final m = PushEnvelope.fromMap(data);
        // Every push: a failed native decline may be waiting (E14).
        unawaited(_replayFailedEnds());
        if (e['route'] == 'probe' || PushClassifier.isHeartbeat(m)) {
          await HeartbeatHandler.send(via: 'voip_push');
          return;
        }
        await CallPushHandler.handle(
          m,
          source: CallPushSource.voip,
          foreground: e['foreground'] == true,
        );
      case 'nativeEnded':
        await _ended('${e['callId'] ?? ''}', const {});
      case 'instantAccepted':
        // iOS: the native answer's `/instant-call/host-accept` reply (Talk
        // Now): the call record Callend bills.
        final callId = '${e['callId'] ?? ''}';
        final record = '${e['serverCallId'] ?? ''}';
        if (callId.isNotEmpty && record.isNotEmpty) {
          CallSignals.onInstantAccepted(callId, record);
        }
      case 'updateCallFailed':
        // CALL-BREAKING otherwise: the server never learns the answer, the
        // caller keeps ringing and the call is billed as missed (I1).
        final callId = '${e['callId'] ?? ''}';
        if (callId.isNotEmpty) await CallSignals.onNativeUpdateFailed(callId);
      case 'unlocked':
        // The keychain / prefs may have been unreadable at a VoIP boot
        // (E33, I10): what the locked boot cached is stale.
        if (!SessionStore.instance.value.isAuthenticated) {
          try {
            await AppPrefs.instance.reloadCache();
          } catch (_) {}
          await SessionStore.instance.restore();
        }
        await CallSignals.onDeviceUnlocked();
    }
  }

  /// A VoIP push native queued before Dart listened (cold start). A
  /// background ring whose CallKit call is gone was declined, ended or
  /// timed out on CallKit before Dart ran: replaying it would resurrect a
  /// dead call (I8), so it is marked ended instead.
  static Future<void> _onQueuedBridge(Map<String, dynamic> e) async {
    final data = e['data'];
    if (Platform.isIOS &&
        e['event'] == 'voipPush' &&
        e['route'] == 'ring' &&
        e['foreground'] != true &&
        data is Map) {
      final callId = PushEnvelope.fromMap(data).callId ?? '';
      if (callId.isNotEmpty) {
        final live = await NativeCallBridge.liveCall();
        if (live == null || '${live['callId'] ?? ''}' != callId) {
          Log.d(_tag, 'queued ring $callId has no CallKit call: ended');
          await NativeCallMarks.markEnded(callId);
          await CallSignals.onEnded(callId);
          return;
        }
      }
    }
    await _onBridge(e);
  }

  // ── cold start / resume ────────────────────────────────────────────────

  /// Cold start (§2.7), before the gate opens: queued bridge events, the
  /// pending accept, the plugin's active calls, failed native ends.
  static Future<void> reconcile() async {
    try {
      // A failed native `/UpdateCall` is retried once the accept it belongs
      // to reached the logic (the retry needs the call).
      final updateFailed = <String>{};
      for (final e in await NativeCallBridge.ready()) {
        if (e['event'] == 'updateCallFailed') {
          final id = '${e['callId'] ?? ''}';
          if (id.isNotEmpty) updateFailed.add(id);
          continue;
        }
        await _bounded(() => _onQueuedBridge(e));
      }
      // The snapshot is consumed (and its call id known) BEFORE the bounded
      // accept: a slow accept that outlives its slot must not make the
      // plugin's active call below replay the same accept (I7).
      final pending = await _takePendingAccept();
      final accepted = pending?.callId;
      if (pending != null) {
        // Sent with apiDone false when native's request failed: no retry
        // on top of it.
        final failed = updateFailed.remove(accepted);
        await _bounded(() => _coldAccept(pending, updateFailed: failed));
      }
      final active = await CallKitService.activeCalls();
      Log.w(
        'CallFlow',
        'reconcile: ${active.length} plugin call(s) '
            '${active.map((c) => '${c.callId}${c.isAccepted ? '(accepted)' : ''}').join(',')}',
      );
      for (final call in active) {
        if (call.isCompliance || call.callId.isEmpty) continue;
        if (call.isAccepted) {
          Log.w('CallAccept', 'reconcile: accepted ${call.callId} → logic');
          if (call.callId == accepted) continue;
          // Dropped by the logic when > 5 min old or closed on the server.
          final failed = updateFailed.remove(call.callId);
          await _bounded(
            () => CallSignals.onColdStartAccept(
              call.extra,
              apiDone: Platform.isIOS && !failed,
            ),
          );
        } else if (await _isLiveRing(call)) {
          // Adopt the ring (store + ringing ack); the system ringer is up.
          await CallPushHandler.adoptBackgroundAck(call.callId);
          await _bounded(() => CallSignals.onColdStartRinging(call.extra));
        } else {
          await _endStale(call);
        }
      }
      for (final id in updateFailed) {
        await _bounded(() => CallSignals.onNativeUpdateFailed(id));
      }
      unawaited(_replayFailedEnds());
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }

  /// `AppLifecycleState.resumed`.
  static Future<void> onResumed() async {
    await _bounded(() async {
      if (Platform.isAndroid) {
        // A background isolate may have queued declines or a refresh.
        try {
          await AppPrefs.instance.reloadCache();
        } catch (_) {}
      }
      await _pendingAccept();
      await _adoptAndroidRing();
      await WalletNotifications.applyPendingRefresh();
    });
    unawaited(_replayFailedEnds());
    await CallSignals.onAppResumed();
  }

  /// iOS: the accept snapshot native saved at CXAnswerCallAction that no
  /// live ACTION_CALL_ACCEPT consumed. Returns its call id. (Android's
  /// background accept goes through `CallSignals.savePendingAccept`, which
  /// the logic's own reconcile picks up.)
  static Future<String?> _pendingAccept() async {
    final pending = await _takePendingAccept();
    if (pending == null) return null;
    await _coldAccept(pending);
    return pending.callId;
  }

  /// Reads (and so consumes) the iOS accept snapshot.
  static Future<_PendingAccept?> _takePendingAccept() async {
    if (!Platform.isIOS) return null;
    final snap = await NativeCallBridge.consumePendingAccept();
    final p = snap?['payload'];
    if (p is! Map) return null;
    final payload = Map<String, dynamic>.from(p);
    final callId = '${payload['callId'] ?? payload['call_id'] ?? ''}';
    return _PendingAccept(
      callId: callId.isEmpty ? null : callId,
      payload: payload,
      updateFailed: snap?['updateFailed'] == true,
    );
  }

  /// Native's `/UpdateCall` failed for it: the logic sends it ([apiDone]
  /// false), which an `alreadyOngoing` reply makes safe (E-86).
  static Future<void> _coldAccept(
    _PendingAccept p, {
    bool updateFailed = false,
  }) => CallSignals.onColdStartAccept(
    p.payload,
    apiDone: !(p.updateFailed || updateFailed),
  );

  /// Android: a ring the FCM background isolate showed while this isolate
  /// was alive in the background never reached this isolate's logic. Opened
  /// from the launcher while it rings → adopt it (the logic shows the
  /// incoming screen when in front).
  static Future<void> _adoptAndroidRing() async {
    if (!Platform.isAndroid || CallController.instance.isOnCall) return;
    for (final call in await CallKitService.activeCalls()) {
      if (call.isAccepted || call.callId.isEmpty) continue;
      if (!await _isLiveRing(call)) continue;
      await CallPushHandler.adoptBackgroundAck(call.callId);
      await CallSignals.onColdStartRinging(call.extra);
      return;
    }
  }

  static Future<bool> _isLiveRing(NativeCall call) async {
    final m = PushEnvelope.fromMap(call.extra);
    if (await NativeCallMarks.isEnded(call.callId)) return false;
    final age = CallPushHandler.ageOf(m.sentAt, DateTime.now());
    if (age != null && age > CallPushHandler.maxRingAge) return false;
    return (m.data['channelName'] ?? m.data['roomId'] ?? '').isNotEmpty &&
        (m.data['token'] ?? m.data['receiverToken'] ?? '').isNotEmpty;
  }

  static Future<void> _endStale(NativeCall call) async {
    if (Platform.isIOS) {
      await NativeCallBridge.endCall(call.callId);
      return;
    }
    await NativeCallMarks.markAppEnded(call.callId);
    await CallKitService.end(call.callId);
  }

  /// iOS native Callend bodies that failed → the decline queue → replay.
  /// Android: notification Declines no engine heard (process dead, A5) →
  /// the headless decline (it skips a call already ended or declined).
  static Future<void> _replayFailedEnds() async {
    for (final body in await NativeCallBridge.drainFailedEnds()) {
      await PendingDeclineQueue.enqueueRaw(body);
    }
    for (final extra in await NativeCallBridge.drainNativeDeclines()) {
      final callId = '${extra['callId'] ?? ''}';
      if (callId.isEmpty) continue;
      await HeadlessCallEnd.decline(callId, extra);
      await CallSignals.onNativeDeclined(callId, apiDone: true, payload: extra);
    }
    try {
      await PendingDeclineQueue.flush();
    } catch (_) {}
  }

  static Future<void> _guard(Future<void> Function() job) async {
    try {
      await job();
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }
}

class _PendingAccept {
  const _PendingAccept({
    required this.callId,
    required this.payload,
    required this.updateFailed,
  });

  final String? callId;
  final Map<String, dynamic> payload;
  final bool updateFailed;
}
