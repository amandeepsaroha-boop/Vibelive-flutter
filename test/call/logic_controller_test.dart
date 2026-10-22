import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_navigator.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/state/call_dedup.dart';

CallSession ring(String id, {String receiverId = '9'}) => CallSession(
  role: CallRole.receiver,
  callId: id,
  channelName: 'c$id',
  token: 't$id',
  callerId: '5',
  receiverId: receiverId,
);

void main() {
  final calls = CallController.instance;
  setUp(calls.reset);
  tearDown(calls.reset);

  group('CallController guards', () {
    test('receive: same call again changes nothing (E-5, E-6)', () {
      expect(calls.receive(ring('1')), isTrue);
      final first = calls.value;
      expect(first.phase, CallPhase.ringing);
      expect(calls.receive(ring('1')), isFalse);
      expect(identical(calls.value, first), isTrue);
      calls.setAccepted();
      expect(calls.receive(ring('1')), isFalse);
      expect(calls.value.phase, CallPhase.accepted);
    });

    test('a different call during a live one is ignored (E-61)', () {
      calls.receive(ring('1'));
      calls.setAccepted();
      expect(calls.receive(ring('2')), isFalse);
      expect(calls.value.callId, '1');
      calls.setConnected();
      expect(calls.receive(ring('2')), isFalse);
      expect(calls.value.callId, '1');
      expect(calls.value.phase, CallPhase.ongoing);
    });

    test('a different ring replaces one that only rings', () {
      calls.receive(ring('1'));
      expect(calls.receive(ring('2')), isTrue);
      expect(calls.value.callId, '2');
    });

    test('setConnected / setAccepted after ended are ignored', () {
      calls.receive(ring('1'));
      calls.setAccepted();
      calls.end();
      expect(calls.value.phase, CallPhase.ended);
      calls.setConnected();
      calls.setAccepted();
      expect(calls.value.phase, CallPhase.ended);
      expect(calls.value.connectedAt, isNull);
    });

    test('setRinging only moves a caller out of calling', () {
      calls.startOutgoing(
        const CallSession(callId: '3', callerId: '9', receiverId: '5'),
      );
      expect(calls.value.phase, CallPhase.calling);
      expect(calls.value.role, CallRole.caller);
      calls.setRinging();
      expect(calls.value.phase, CallPhase.ringing);
      calls
        ..setAccepted()
        ..setConnected()
        ..setRinging();
      expect(calls.value.phase, CallPhase.ongoing);
    });

    test('Agora uid by role, never the session user (E-36, E-93)', () {
      expect(ring('1', receiverId: '12').localUid, 12);
      const caller = CallSession(
        role: CallRole.caller,
        callerId: '7',
        receiverId: '12',
      );
      expect(caller.localUid, 7);
      expect(const CallSession(role: CallRole.caller).localUid, isNull);
    });

    test('duration is wall clock, at least 1 s once connected', () {
      final at = DateTime(2026, 1, 1, 10);
      final s = CallSession(connectedAt: at);
      expect(s.durationSeconds(at), 1);
      expect(s.durationSeconds(at.add(const Duration(seconds: 75))), 75);
      expect(const CallSession().durationSeconds(), 0);
    });
  });

  group('CallDedup', () {
    final dedup = CallDedup.instance;
    setUp(dedup.reset);

    test('ended memory lasts 30 s', () {
      final t = DateTime(2026, 1, 1);
      dedup.markEnded('1', now: t);
      expect(dedup.isEnded('1', now: t.add(const Duration(seconds: 29))), true);
      expect(
        dedup.isEnded('1', now: t.add(const Duration(seconds: 31))),
        false,
      );
    });

    test('signals repeat within 4 s are dropped (E-3)', () {
      final t = DateTime(2026, 1, 1);
      expect(dedup.shouldHandleSignal('ended', '1', now: t), isTrue);
      expect(
        dedup.shouldHandleSignal(
          'ended',
          '1',
          now: t.add(const Duration(seconds: 3)),
        ),
        isFalse,
      );
      expect(dedup.shouldHandleSignal('ringing', '1', now: t), isTrue);
      expect(
        dedup.shouldHandleSignal(
          'ended',
          '1',
          now: t.add(const Duration(seconds: 5)),
        ),
        isTrue,
      );
    });

    test('claims last 15 s and are released on action (E-2)', () {
      final t = DateTime(2026, 1, 1);
      expect(dedup.claim('1|a', now: t), isTrue);
      expect(
        dedup.claim('1|a', now: t.add(const Duration(seconds: 10))),
        false,
      );
      dedup.releaseClaims('1');
      expect(dedup.claim('1|a', now: t.add(const Duration(seconds: 11))), true);
    });

    test('ack once; a failed ack may be retried', () {
      expect(dedup.beginAck('1'), isTrue);
      expect(dedup.beginAck('1'), isFalse, reason: 'in flight');
      dedup.finishAck('1', ok: false);
      expect(dedup.beginAck('1'), isTrue);
      dedup.finishAck('1', ok: true);
      expect(dedup.beginAck('1'), isFalse);
    });

    test('UpdateCall once per call, retried after a failure', () {
      expect(dedup.beginUpdateCall('1'), isTrue);
      expect(dedup.beginUpdateCall('1'), isFalse);
      dedup.failUpdateCall('1');
      expect(dedup.beginUpdateCall('1'), isTrue);
    });
  });

  group('CallRouteRules', () {
    test('empty call screen bounces (E-60)', () {
      expect(CallRouteRules.callScreenIsEmpty(CallSession.idle), isTrue);
      expect(CallRouteRules.callScreenIsEmpty(ring('1')), isFalse);
      expect(
        CallRouteRules.callScreenIsEmpty(
          const CallSession(phase: CallPhase.ended, callId: '1'),
        ),
        isFalse,
      );
    });

    test('incoming screen: answered → call, over → exit after bootstrap', () {
      IncomingRouteAction act(
        CallSession s, {
        bool boot = false,
        bool saw = false,
      }) => CallRouteRules.incoming(s, bootstrapped: boot, sawRinging: saw);
      expect(
        act(const CallSession(phase: CallPhase.accepted, callId: '1')),
        IncomingRouteAction.toCall,
      );
      expect(
        act(ring('1').copyWith(phase: CallPhase.ringing)),
        IncomingRouteAction.stay,
      );
      // Hydration gap: mounted before the store was filled.
      expect(act(CallSession.idle), IncomingRouteAction.stay);
      expect(act(CallSession.idle, boot: true), IncomingRouteAction.exit);
      expect(act(CallSession.idle, saw: true), IncomingRouteAction.exit);
    });
  });
}
