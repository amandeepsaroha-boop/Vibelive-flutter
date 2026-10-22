import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_navigator.dart';
import 'package:vibelive/app/callscreen/helper/call_ringtone.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/call_timers.dart';
import 'package:vibelive/app/callscreen/helper/engine/call_engine.dart';
import 'package:vibelive/app/callscreen/helper/state/call_store.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'logic_fakes.dart';

const ack = '/api/call/receiver-ringing-ack';
const callEnd = '/api/call/Callend';
const updateCall = '/api/UpdateCall';

void main() {
  final calls = CallController.instance;
  late FakeBackend backend;
  late FakeRingtone ringtone;
  late FakePlatform platform;

  setUpAll(initCallTestEnv);
  setUp(() async {
    final env = await resetCallTestEnv();
    backend = env.backend;
    ringtone = env.ringtone;
    platform = env.platform;
  });
  tearDown(resetCallState);

  /// A caller-side call in [phase] (this user, id 9, called user 5).
  void outgoing({CallPhase phase = CallPhase.calling, String id = '77'}) {
    calls.startOutgoing(
      CallSession(
        callId: id,
        channelName: 'call_9_5_1',
        token: agoraToken(),
        callerId: '9',
        receiverId: '5',
        sentAt: DateTime.now(),
      ),
    );
    if (phase == CallPhase.ringing) calls.setRinging();
    if (phase == CallPhase.accepted) calls.setAccepted();
    if (phase == CallPhase.ongoing) {
      calls
        ..setAccepted()
        ..setConnected();
    }
  }

  group('onInvite', () {
    test('rings: store filled, one ack, ring timer armed', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await settle();
      final s = calls.value;
      expect(s.phase, CallPhase.ringing);
      expect(s.role, CallRole.receiver);
      expect(s.callId, '42');
      expect(s.remote.name, 'Ravi Kumar');
      expect(backend.to('POST', ack), hasLength(1));
      expect(backend.lastBody('POST', ack), {
        'callId': '42',
        'receiverId': '9',
      });
      expect(CallTimers.instance.isArmed(CallTimers.incomingRing), isTrue);
      // Background: the system ringer rings, not the app.
      expect(ringtone.log, isNot(contains('start:incoming')));
    });

    test('a duplicate invite (FCM + VoIP, re-delivery) acks once', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallSignals.onInvite(
        ringPush(),
        foreground: false,
        source: CallPushSource.voip,
      );
      await CallSignals.onInvite(ringPush(), foreground: false);
      await settle();
      expect(backend.to('POST', ack), hasLength(1));
      expect(calls.value.phase, CallPhase.ringing);
    });

    test('stale: 45 s for VoIP, 120 s otherwise (E-13)', () async {
      final at = DateTime.now().subtract(const Duration(seconds: 60));
      await CallSignals.onInvite(
        ringPush(sentAt: at),
        foreground: false,
        source: CallPushSource.voip,
      );
      expect(calls.value.phase, CallPhase.idle);
      await CallSignals.onInvite(ringPush(sentAt: at), foreground: false);
      expect(calls.value.phase, CallPhase.ringing);

      resetCallState();
      await CallSignals.onInvite(
        ringPush(
          callId: '43',
          sentAt: DateTime.now().subtract(const Duration(minutes: 3)),
        ),
        foreground: false,
      );
      expect(calls.value.phase, CallPhase.idle);
      await settle();
      expect(backend.to('POST', ack), hasLength(1), reason: 'only call 42');
    });

    test('self-call and calls for someone else are dropped', () async {
      await CallSignals.onInvite(
        ringPush(callerId: '9', receiverId: '5'),
        foreground: false,
      );
      expect(calls.value.phase, CallPhase.idle, reason: 'E-19');
      await CallSignals.onInvite(ringPush(receiverId: '1'), foreground: false);
      expect(calls.value.phase, CallPhase.idle, reason: 'E-75');
      await settle();
      expect(backend.to('POST', ack), isEmpty);
    });

    test('no join creds never ring (E-7)', () async {
      await CallSignals.onInvite({
        'type': 'CallTimer',
        'callId': '42',
        'callerId': '5',
      }, foreground: false);
      expect(calls.value.phase, CallPhase.idle);
    });

    test('CALL_RINGING delivered as an invite never rings (E-75)', () async {
      await CallSignals.onInvite(
        ringPush(extra: {'type': 'CALL_RINGING'}),
        foreground: false,
      );
      expect(calls.value.phase, CallPhase.idle);
    });

    test('a ring for a call that just ended is ignored (E-18)', () async {
      await CallSignals.onEnded('42', status: 'missed');
      await CallSignals.onInvite(ringPush(), foreground: false);
      expect(calls.value.phase, CallPhase.idle);
    });

    test('VoIP re-delivery of a handled call is dropped (E-4)', () async {
      await CallStore.markHandled('42');
      await CallSignals.onInvite(
        ringPush(),
        foreground: false,
        source: CallPushSource.voip,
      );
      expect(calls.value.phase, CallPhase.idle);
    });

    test('a different ring during a live call is ignored (E-61)', () async {
      outgoing(phase: CallPhase.ongoing);
      await CallSignals.onInvite(ringPush(), foreground: false);
      expect(calls.value.callId, '77');
      expect(calls.value.phase, CallPhase.ongoing);
    });

    test('foreground: in-app ringtone, the incoming screen parked', () async {
      final presenting = CallSignals.onInvite(ringPush(), foreground: true);
      await settle(50);
      expect(ringtone.log, contains('start:incoming'));
      await presenting; // the 2 s hold (router not ready in tests)
      expect(CallNavigator.debugPending, AppRoutes.incomingCall);
      // Any phase change away from ringing stops it.
      calls.reset();
      await settle();
      expect(CallRingtone.playing, isNull);
    });
  });

  group('caller signals', () {
    test('CALL_RINGING moves only a matching caller to ringing', () async {
      outgoing();
      CallSignals.onRemoteRinging('999');
      expect(calls.value.phase, CallPhase.calling);
      CallSignals.onRemoteRinging('77');
      expect(calls.value.phase, CallPhase.ringing);

      resetCallState();
      await CallSignals.onInvite(ringPush(), foreground: false);
      CallSignals.onRemoteRinging('42');
      expect(calls.value.phase, CallPhase.ringing);
      expect(calls.value.role, CallRole.receiver);
    });

    test('accepted / CallTimer → caller ongoing; receiver untouched', () async {
      outgoing(phase: CallPhase.ringing);
      CallSignals.onOngoingSignal('77', const {'type': 'CallTimer'});
      expect(calls.value.phase, CallPhase.ongoing);
      expect(calls.value.everConnected, isTrue);

      resetCallState();
      await CallSignals.onInvite(ringPush(), foreground: false);
      CallSignals.onOngoingSignal('42', const {'type': 'CallTimer'});
      expect(calls.value.phase, CallPhase.ringing, reason: 'mem #5');
    });

    test('a documentId-keyed push matches a numeric call (E-71)', () {
      outgoing(phase: CallPhase.ringing);
      CallSignals.onOngoingSignal('doc-77', {
        'sentTime': '${DateTime.now().millisecondsSinceEpoch + 1000}',
      });
      expect(calls.value.phase, CallPhase.ongoing);
      expect(calls.value.callId, '77', reason: 'the numeric id stays');
      expect(calls.value.callDocumentId, 'doc-77');
    });
  });

  group('onEnded', () {
    // With no call screen on show (no router in tests) an ended call goes
    // straight back to idle: record that it passed through `ended`.
    late List<CallPhase> phases;
    void record() => phases.add(calls.value.phase);
    setUp(() {
      phases = [];
      calls.session.addListener(record);
    });
    tearDown(() => calls.session.removeListener(record));

    test('receiver ringing → idle, no API', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallSignals.onEnded('42', status: 'missed');
      expect(calls.value.phase, CallPhase.idle);
      expect(platform.log, contains('end:42'));
      await settle();
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('caller calling / ringing → ended (E-46), no Callend', () async {
      outgoing();
      await CallSignals.onEnded('77', status: 'declined');
      expect(phases, contains(CallPhase.ended));
      expect(calls.value.phase.isActive, isFalse);
      phases.clear();
      outgoing(id: '78', phase: CallPhase.ringing);
      await CallSignals.onEnded('78');
      expect(phases, contains(CallPhase.ended));
      expect(calls.value.phase.isActive, isFalse);
      await settle();
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('accepted (headless) → ended (E-45)', () async {
      outgoing(phase: CallPhase.accepted);
      await CallSignals.onEnded('77');
      expect(phases.last, isNot(CallPhase.accepted));
      expect(phases, contains(CallPhase.ended));
      expect(calls.value.phase.isActive, isFalse);
    });

    test('ongoing is left to Agora (E-47); a server end closes it', () async {
      outgoing(phase: CallPhase.ongoing);
      await CallSignals.onEnded('77');
      expect(calls.value.phase, CallPhase.ongoing);
      expect(CallTimers.instance.isArmed(CallTimers.endedPush), isTrue);

      // Admin force-end: now.
      resetCallState();
      outgoing(phase: CallPhase.ongoing, id: '79');
      await CallSignals.onEnded('79', status: 'force_complete_by_admin');
      expect(phases, contains(CallPhase.ended));
      expect(calls.value.phase.isActive, isFalse);
      await settle();
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('other calls and repeats are ignored', () async {
      outgoing();
      await CallSignals.onEnded('1');
      expect(calls.value.phase, CallPhase.calling);
    });
  });

  group('answered elsewhere (E-76)', () {
    test('dismisses a ring on another device', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      CallSignals.onAnsweredElsewhere('42');
      expect(calls.value.phase, CallPhase.idle);
    });

    test('ignored by the device that answered', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
      CallSignals.onAnsweredElsewhere('42');
      expect(calls.value.phase, CallPhase.accepted);
    });
  });

  group('native', () {
    test(
      'accept: store accepted, uid from the call, no 2nd UpdateCall',
      () async {
        await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
        await settle(50);
        final s = calls.value;
        expect(s.phase, CallPhase.accepted);
        expect(s.autoAccept, isTrue);
        expect(s.localUid, 9);
        expect(backend.to('POST', updateCall), isEmpty, reason: 'mem #15');
        // Straight to /call (parked: no router yet), never /call/incoming.
        expect(CallNavigator.debugPending, AppRoutes.call);
        await CallSignals.onAppResumed();
        expect(CallNavigator.debugPending, AppRoutes.call);
      },
    );

    test('accept without native UpdateCall sends it with the device', () async {
      await CallSignals.onNativeAccepted(ringPush());
      await settle(50);
      expect(backend.lastBody('POST', updateCall), {
        'callId': '42',
        'callerId': '5',
        'receiverId': '9',
        'status': 'ongoing',
        'type': 'voiceCall',
        'answeredDeviceId': 'ios-device-1',
      });
    });

    test('accept of an ended call only clears the native UI (E-17)', () async {
      await CallSignals.onEnded('42');
      await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
      expect(calls.value.phase, CallPhase.idle);
      expect(platform.log, contains('end:42'));
    });

    test('ended on the system UI: no API (mem #15)', () async {
      await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
      await CallSignals.onNativeEnded('42');
      expect(calls.value.phase, anyOf(CallPhase.ended, CallPhase.idle));
      await settle();
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('declined natively: local reset; API only when asked', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallSignals.onNativeDeclined('42');
      expect(calls.value.phase, CallPhase.idle);
      await settle();
      expect(backend.to('POST', callEnd), isEmpty);

      await CallSignals.onNativeDeclined(
        '43',
        apiDone: false,
        payload: ringPush(callId: '43'),
      );
      await settle();
      final body = backend.lastBody('POST', callEnd);
      expect(body['callId'], '43');
      expect(body['status'], 'declined');
      expect(body['endedById'], 9);
    });

    test('timeout dismisses a ring; late ones are ignored', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      CallSignals.onNativeTimeout('42');
      expect(calls.value.phase, CallPhase.idle);
      CallSignals.onNativeTimeout('42');
      expect(calls.value.phase, CallPhase.idle);
    });

    test('a pending accept from another isolate is reconciled', () async {
      await CallSignals.savePendingAccept(ringPush(), apiDone: true);
      await CallSignals.reconcile();
      await settle(50);
      expect(calls.value.phase, CallPhase.accepted);
      // The cold-start check used the filter route (E-85).
      final status = backend.to('GET', '/api/calls').single.o.queryParameters;
      expect(status[r'filters[id][$eq]'], '42');
    });

    test(
      'a cold-start accept closed on the server is dropped (E-16)',
      () async {
        backend.replies['GET /api/calls'] = (_) => {
          'data': [
            {'id': 42, 'callStatus': 'completed'},
          ],
        };
        await CallSignals.onColdStartAccept(ringPush());
        expect(calls.value.phase, CallPhase.idle);
        expect(platform.log, contains('end:42'));
      },
    );
  });

  group('callback request (PING_CLIENT)', () {
    test('shown to the client, never to the expert who sent it', () {
      CallSignals.onCallbackRequest({'type': 'PING_CLIENT', 'expertId': '9'});
      expect(CallSignals.callbackRequest.value, isNull, reason: 'E-73');
      CallSignals.onCallbackRequest({
        'type': 'PING_CLIENT',
        'expertId': '5',
        'expertName': 'Meera',
      });
      expect(CallSignals.callbackRequest.value?.data['expertName'], 'Meera');
      CallSignals.clearCallbackRequest();
      expect(CallSignals.callbackRequest.value, isNull);
    });
  });

  test('the engine is never joined by a background ring', () async {
    await CallSignals.onInvite(ringPush(), foreground: false);
    expect(CallEngine.instance.isJoined, isFalse);
    expect(CallEngine.instance.rtc, isNull);
  });
}
