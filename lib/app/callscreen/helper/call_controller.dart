import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'call_session.dart';

/// The one call (RN `call.store`), outside widgets. Screens only observe
/// [session] / [elapsed]; push handlers, CallKit events and user actions
/// move it through the guarded transitions below. Every guard is
/// load-bearing (see `docs/call_architecture.md`, RN spec §2.1).
class CallController {
  CallController._();
  static final instance = CallController._();

  final _session = ValueNotifier<CallSession>(CallSession.idle);
  final _elapsed = ValueNotifier<int>(0);
  final _onCall = ValueNotifier<bool>(false);
  Timer? _ticker;

  /// Phases whose start is stamped in [CallSession.phaseSince].
  static const _timed = {
    CallPhase.calling,
    CallPhase.ringing,
    CallPhase.accepted,
    CallPhase.ongoing,
  };

  ValueListenable<CallSession> get session => _session;
  CallSession get value => _session.value;

  /// Seconds since connect (wall clock), ticking while [CallPhase.ongoing].
  /// Only the timer pill listens to it.
  ValueListenable<int> get elapsed => _elapsed;

  bool get isOnCall => value.phase.isActive;

  /// [isOnCall] as a listenable that only fires when a call starts or
  /// stops (splash, return-to-call bar), not on every session change.
  ValueListenable<bool> get onCall => _onCall;

  /// Caller: `/initiateCall` succeeded → [CallPhase.calling]. Always takes
  /// the slot (the backend's busy check guards a second call).
  void startOutgoing(CallSession call) {
    _stopTicker();
    _elapsed.value = 0;
    _set(
      call.copyWith(phase: CallPhase.calling, role: CallRole.caller),
      force: true,
    );
  }

  /// Receiver: a ring → [CallPhase.ringing]. False (nothing changed) when
  /// it is the call already in progress (re-delivered push, E-5/E-6: a second
  /// fill would restart the join) or when another call is live (E-61: a
  /// different ring never overwrites a call in progress).
  bool receive(CallSession call) {
    final now = value;
    if (now.phase.isActive && now.isSameCall(call.callId)) return false;
    if (now.phase.isActive && now.phase != CallPhase.ringing) return false;
    _stopTicker();
    _elapsed.value = 0;
    _set(
      call.copyWith(phase: CallPhase.ringing, role: CallRole.receiver),
      force: true,
    );
    return true;
  }

  /// Caller: the receiver's phone rings (ack push). Never moves a call
  /// backwards out of accepted / ongoing.
  void setRinging() {
    final p = value.phase;
    if (p != CallPhase.calling) return;
    _set(value.copyWith(phase: CallPhase.ringing));
  }

  /// Answered ("connecting"). Keeps ongoing; ignored once ended.
  void setAccepted() {
    final p = value.phase;
    if (p == CallPhase.idle || p == CallPhase.ended || p == CallPhase.ongoing) {
      return;
    }
    _set(value.copyWith(phase: CallPhase.accepted));
  }

  /// Both sides in the channel → [CallPhase.ongoing]; the timer starts from
  /// [at] (default now) once. Unlike RN, never revives an ended call.
  void setConnected({DateTime? at}) {
    final p = value.phase;
    if (p == CallPhase.idle || p == CallPhase.ended) return;
    if (p == CallPhase.ongoing) return;
    _set(
      value.copyWith(
        phase: CallPhase.ongoing,
        connectedAt: value.connectedAt ?? at ?? clock.now(),
      ),
    );
    _startTicker();
    // `call_started` and every other call event: CallAnalytics.
  }

  /// → [CallPhase.ended] (summary / feedback). Idempotent.
  void end() {
    if (value.phase == CallPhase.ended || value.phase == CallPhase.idle) {
      return;
    }
    _stopTicker();
    _set(value.copyWith(phase: CallPhase.ended, endedAt: clock.now()));
  }

  /// → idle; clears the call.
  void reset() {
    _stopTicker();
    _elapsed.value = 0;
    _set(CallSession.idle, force: true);
  }

  /// Merge late details (documentId, a better name or photo, uid) into the
  /// live call. Ignored when idle.
  void update(CallSession Function(CallSession current) change) {
    if (value.phase == CallPhase.idle) return;
    _set(change(value));
  }

  void _set(CallSession change, {bool force = false}) {
    final prev = _session.value;
    if (!force && identical(change, prev)) return;
    final moved = change.phase != prev.phase || change.callId != prev.callId;
    final next = moved && _timed.contains(change.phase)
        ? change.copyWith(phaseSince: clock.now())
        : change;
    _session.value = next;
    _onCall.value = next.phase.isActive;
  }

  void _startTicker() {
    _stopTicker();
    void tick() {
      final start = value.connectedAt;
      if (start == null) return;
      final s = clock.now().difference(start).inSeconds;
      if (s != _elapsed.value) _elapsed.value = s < 0 ? 0 : s;
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Tests only.
  @visibleForTesting
  void debugSet(CallSession session) {
    _session.value = session;
    _onCall.value = session.phase.isActive;
    if (session.phase == CallPhase.ongoing) {
      _startTicker();
    } else {
      _stopTicker();
    }
  }
}
