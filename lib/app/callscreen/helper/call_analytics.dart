import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/session/session_store.dart';
import 'call_controller.dart';
import 'call_session.dart';

/// Why a call ended, as the end flows tag it ([CallAnalytics.reason]).
abstract final class CallEndReason {
  /// The user's hang-up button (call screen, return bar, notification).
  static const userHangup = 'user_hangup';

  /// The other side hung up (left the channel on purpose).
  static const remoteHangup = 'remote_hangup';

  /// The other side dropped and did not come back in the grace period.
  static const remoteDropped = 'remote_dropped';

  /// The ended push / server said the call is over.
  static const remoteEnded = 'remote_ended';
  static const adminEnded = 'admin_ended';

  /// The caller's balance ran out (client-side max duration).
  static const balanceExhausted = 'balance_exhausted';
  static const networkLost = 'network_lost';
  static const tokenExpired = 'token_expired';

  /// The caller gave up waiting: nobody answered in time.
  static const noAnswer = 'no_answer';

  /// Answered, but the other side never joined the channel.
  static const peerNeverJoined = 'peer_never_joined';
  static const joinFailed = 'join_failed';

  /// Another device of this user took the call.
  static const otherDevice = 'other_device';
  static const answeredElsewhere = 'answered_elsewhere';

  /// Hung up on the system call UI (CallKit / the Android notification).
  static const systemUi = 'system_ui';

  /// Receiver: declined (in-app, system UI, or decline + block / report).
  static const declined = 'declined';

  /// Receiver: the ring went away (caller cancelled) / timed out.
  static const callerCancelled = 'caller_cancelled';
  static const ringTimeout = 'ring_timeout';

  /// In-call block / report.
  static const safetyBlock = 'safety_block';
  static const safetyReport = 'safety_report';
  static const signOut = 'sign_out';
}

/// Every call event, to Firebase and Meta, from ONE place: the call's
/// phase changes in [CallController] (whichever flow moved it: in-app,
/// CallKit, push, Android notification). The end flows only tag why a call
/// ends ([reason]).
///
/// | event              | when                                             |
/// |--------------------|--------------------------------------------------|
/// | call_initiated     | caller: `/initiateCall` succeeded                |
/// | call_incoming      | receiver: the ring is shown                      |
/// | call_ringing       | caller: the host's phone rings                   |
/// | call_accepted      | answered (both roles, `role`)                    |
/// | call_started       | connected, the timer runs                        |
/// | call_ended         | a connected call finished (`end_reason`, length) |
/// | call_cancelled     | caller hung up before an answer                  |
/// | call_not_answered  | caller: nobody answered in time                  |
/// | call_rejected      | caller: the host declined / server ended it      |
/// | call_declined      | receiver declined                                |
/// | call_missed        | receiver never answered (caller left / timeout)  |
/// | call_failed        | could not connect (join failed, peer never came) |
abstract final class CallAnalytics {
  static CallSession _prev = CallSession.idle;
  static bool _attached = false;
  static final _reasons = <String, String>{};
  static final _ringStart = <String, DateTime>{};
  static final _accepted = <String>{};
  static final _rates = <String, double>{};

  /// From `CallFlow.attach` (before any call event).
  static void attach() {
    if (_attached) return;
    _attached = true;
    _prev = CallController.instance.value;
    CallController.instance.session.addListener(_onChange);
  }

  /// Why [callId] is about to end. The first reason wins (a hang-up that
  /// follows a "remote left" is still the remote's).
  static void reason(String? callId, String reason) {
    if (callId == null || callId.isEmpty) return;
    _reasons.putIfAbsent(callId, () => reason);
    _trim(_reasons);
  }

  /// The per-minute rate of an outgoing call (from the host card).
  static void rate(String? callId, double? ratePerMin) {
    if (callId == null || ratePerMin == null) return;
    _rates[callId] = ratePerMin;
    _trim(_rates);
  }

  /// A ring declined on the system UI that the app never showed (killed
  /// app, CallKit): no phase change to see, so it is logged here.
  static void declinedUnseen(String callId, {required bool video}) {
    if (_prev.isSameCall(callId)) return;
    Analytics.log('call_declined', {
      'call_id': callId,
      'call_type': video ? 'video' : 'audio',
      'role': 'receiver',
      'end_reason': CallEndReason.declined,
      'source': 'system_ui',
    });
  }

  static void _onChange() {
    final s = CallController.instance.value;
    final p = _prev;
    _prev = s;
    final same = s.callId != null && s.callId == p.callId;
    if (same && s.phase == p.phase) return;
    // Left a live phase without the ended one (a ring dismissed or
    // declined, sign-out: straight to idle), or another call took the slot.
    if (!same && p.callId != null && p.phase.isActive) _over(p);
    final id = s.callId;
    if (id == null) return;
    switch (s.phase) {
      case CallPhase.calling:
        _ringStart[id] = clock.now();
        _trim(_ringStart);
        _log('call_initiated', s);
      case CallPhase.ringing:
        if (s.isCaller) {
          _log('call_ringing', s);
        } else {
          _ringStart[id] = clock.now();
          _trim(_ringStart);
          _log('call_incoming', s, {
            'locked': s.openedLocked,
            'auto_accept': s.autoAccept,
          });
        }
      case CallPhase.accepted:
        if (_accepted.add(id)) {
          _trim(_accepted);
          _log('call_accepted', s, {'ring_seconds': _ringSeconds(id)});
        }
      case CallPhase.ongoing:
        _started(s);
      case CallPhase.ended:
        if (p.phase.isActive || !same) _over(s);
      case CallPhase.idle:
        break;
    }
  }

  /// Connected: `call_started`, plus the first-call milestone per user.
  static void _started(CallSession s) {
    final id = s.callId!;
    // A caller connecting without an accepted phase still answered.
    if (_accepted.add(id)) {
      _trim(_accepted);
      _log('call_accepted', s, {'ring_seconds': _ringSeconds(id)});
    }
    _log('call_started', s, {'rate_per_min': _rates[id]});
    final user = _userKey();
    if (user == null) return;
    Analytics.logOncePersisted(
      '${s.isCaller ? 'first_call_started' : 'host_first_call_started'}_$user',
      s.isCaller ? 'first_call_started' : 'host_first_call_started',
      _params(s),
    );
  }

  static void _over(CallSession s) {
    final id = s.callId;
    if (id == null) return;
    final reason = _reasons.remove(id);
    final rate = _rates.remove(id);
    final accepted = _accepted.remove(id);
    final ring = _ringSeconds(id);
    _ringStart.remove(id);

    if (s.everConnected) {
      final seconds = _duration(s);
      final params = {
        'end_reason': reason ?? CallEndReason.remoteEnded,
        'duration_seconds': seconds,
        'duration_minutes': (seconds / 60).ceil(),
        'duration_bucket': _bucket(seconds),
        'rate_per_min': rate,
      };
      _log('call_ended', s, params);
      final user = _userKey();
      if (user != null) {
        final event = s.isCaller
            ? 'first_call_completed'
            : 'host_first_call_completed';
        Analytics.logOncePersisted(
          '${event}_$user',
          event,
          {..._params(s), ...params},
        );
      }
      return;
    }

    final r = reason ?? (s.isCaller ? CallEndReason.remoteEnded : null);
    final String event;
    if (r == CallEndReason.joinFailed ||
        r == CallEndReason.peerNeverJoined ||
        r == CallEndReason.networkLost ||
        r == CallEndReason.tokenExpired ||
        (accepted && r != CallEndReason.declined && !s.isCaller)) {
      event = 'call_failed';
    } else if (s.isCaller) {
      event = switch (r) {
        CallEndReason.noAnswer => 'call_not_answered',
        CallEndReason.remoteEnded ||
        CallEndReason.remoteHangup ||
        CallEndReason.adminEnded => 'call_rejected',
        _ => 'call_cancelled',
      };
    } else {
      event = r == CallEndReason.declined ||
              r == CallEndReason.safetyBlock ||
              r == CallEndReason.safetyReport
          ? 'call_declined'
          : 'call_missed';
    }
    _log(event, s, {
      'end_reason': r ?? CallEndReason.callerCancelled,
      'ring_seconds': ring,
      'was_accepted': accepted,
    });
  }

  static void _log(
    String event,
    CallSession s, [
    Map<String, Object?> extra = const {},
  ]) => Analytics.log(event, {..._params(s), ...extra});

  static Map<String, Object?> _params(CallSession s) {
    String? clean(String? v) =>
        v == null || v.isEmpty || v.toLowerCase() == 'null' ? null : v;
    return {
      'call_id': s.callId ?? s.callDocumentId,
      'call_type': s.isVideo ? 'video' : 'audio',
      'role': s.isCaller ? 'caller' : 'receiver',
      'host_id': s.isCaller
          ? clean(s.receiverDocId) ?? clean(s.remote.documentId)
          : null,
      'peer_id': clean(s.remote.documentId) ?? clean(s.remote.id),
      'category': clean(s.categoryName) ?? clean(s.category),
      'instant_call': s.isInstantCall,
      'company_call': s.callerIsCompany,
    };
  }

  static int? _ringSeconds(String id) {
    final start = _ringStart[id];
    return start == null ? null : clock.now().difference(start).inSeconds;
  }

  static int _duration(CallSession s) {
    final start = s.connectedAt;
    if (start == null) return 0;
    final end = s.endedAt ?? clock.now();
    final secs = end.difference(start).inSeconds;
    return secs < 1 ? 1 : secs;
  }

  static String _bucket(int seconds) => switch (seconds) {
    < 60 => 'under_1m',
    < 300 => '1_5m',
    < 900 => '5_15m',
    < 1800 => '15_30m',
    _ => 'over_30m',
  };

  static String? _userKey() {
    final s = SessionStore.instance.value;
    return s.userDocumentId ?? s.userId?.toString();
  }

  static void _trim(Object store) {
    if (store is Map && store.length > 30) store.remove(store.keys.first);
    if (store is Set && store.length > 30) store.remove(store.first);
  }

  @visibleForTesting
  static void debugReset() {
    CallController.instance.session.removeListener(_onChange);
    _attached = false;
    _prev = CallSession.idle;
    _reasons.clear();
    _ringStart.clear();
    _accepted.clear();
    _rates.clear();
  }
}
