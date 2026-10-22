import 'package:flutter/foundation.dart';

import 'call_constants.dart';

/// In-memory duplicate guards (RN `SystemIncomingCall.endedCallIds`,
/// CallManager's signal / claim maps and once-per-call refs). One call
/// reaches the app through FCM, VoIP, the CallKit plugin, a notification
/// tap and the cold-start reconcile at once; these decide which one acts.
/// The durable half (handled VoIP ids, pending accept) is `CallStore`.
class CallDedup {
  CallDedup._();
  static final instance = CallDedup._();

  final _ended = <String, DateTime>{};
  final _signals = <String, DateTime>{};
  final _claims = <String, DateTime>{};
  final _acked = <String>{};
  final _acking = <String>{};
  final _updateCall = <String>{};
  final _answered = <String>{};

  /// Ended within [CallTimings.endedMemory] (E-18): no ring, no present.
  bool isEnded(String? callId, {DateTime? now}) {
    if (callId == null || callId.isEmpty) return false;
    final at = _ended[callId];
    if (at == null) return false;
    if ((now ?? DateTime.now()).difference(at) > CallTimings.endedMemory) {
      _ended.remove(callId);
      return false;
    }
    return true;
  }

  void markEnded(String? callId, {DateTime? now}) {
    if (callId == null || callId.isEmpty) return;
    final t = now ?? DateTime.now();
    _sweep(t);
    _ended[callId] = t;
  }

  /// False for a `kind` signal (ringing / ended) of [callId] seen in the
  /// last [CallTimings.signalDedup] (E-3). Records it otherwise.
  bool shouldHandleSignal(String kind, String callId, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _sweep(t);
    final key = '$kind:$callId';
    final seen = _signals[key];
    if (seen != null && t.difference(seen) < CallTimings.signalDedup) {
      return false;
    }
    _signals[key] = t;
    return true;
  }

  /// False when the same push ([fingerprint]) was claimed in the last
  /// [CallTimings.claimTtl] (E-2).
  bool claim(String fingerprint, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _sweep(t);
    final seen = _claims[fingerprint];
    if (seen != null && t.difference(seen) < CallTimings.claimTtl) {
      return false;
    }
    _claims[fingerprint] = t;
    return true;
  }

  /// Accept / decline / end: a genuinely new ring for the id may come again.
  void releaseClaims(String callId) =>
      _claims.removeWhere((k, _) => k.startsWith('$callId|'));

  /// Ringing ack once per call: true = send it now (RN `ackedCallsRef` +
  /// `ackingCallsRef`). [finishAck] records the outcome.
  bool beginAck(String callId) {
    if (_acked.contains(callId) || _acking.contains(callId)) return false;
    _acking.add(callId);
    return true;
  }

  /// A failed ack may be retried by a later delivery.
  void finishAck(String callId, {required bool ok}) {
    _acking.remove(callId);
    if (ok) _acked.add(callId);
  }

  /// `/UpdateCall ongoing` once per call (RN `autoAcceptSyncedRef`).
  bool beginUpdateCall(String callId) => _updateCall.add(callId);

  /// Removed on failure so a later delivery retries.
  void failUpdateCall(String callId) => _updateCall.remove(callId);

  bool updateCallSent(String callId) => _updateCall.contains(callId);

  /// This device answered [callId] (in-app or system UI). A
  /// `CALL_ANSWERED_ELSEWHERE` for it is ignored here (E-76).
  void markAnswered(String callId) => _answered.add(callId);
  bool answeredHere(String callId) => _answered.contains(callId);

  void _sweep(DateTime now) {
    _ended.removeWhere((_, at) => now.difference(at) > CallTimings.endedMemory);
    _signals.removeWhere(
      (_, at) => now.difference(at) > CallTimings.signalDedup,
    );
    _claims.removeWhere((_, at) => now.difference(at) > CallTimings.claimTtl);
    // Once-per-call sets only ever grow by one per call; keep them small.
    for (final set in [_acked, _updateCall, _answered]) {
      if (set.length > 100) set.remove(set.first);
    }
  }

  @visibleForTesting
  void reset() {
    _ended.clear();
    _signals.clear();
    _claims.clear();
    _acked.clear();
    _acking.clear();
    _updateCall.clear();
    _answered.clear();
  }
}
