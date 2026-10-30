import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/instant_call/instant_call_api.dart';
import 'package:vibelive/app/api/instant_call/instant_call_models.dart';
import 'package:vibelive/app/callscreen/helper/call_actions.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_payload.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/flows/end_flow.dart';
import 'package:vibelive/app/callscreen/helper/native/headless_call_end.dart';
import 'package:vibelive/app/callscreen/helper/native/native_call_marks.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';

import 'logic_fakes.dart';

/// Talk Now (instant call), as the backend runs it: a ring is an
/// instant-call SESSION (its callId is the session id); a host's accept /
/// decline go to `/instant-call/*`, the accept creates the call record that
/// Callend bills, and an end for the ring may carry only the session id.
void main() {
  final calls = CallController.instance;
  late FakeBackend backend;

  const hostAccept = '/api/instant-call/host-accept';
  const hostDecline = '/api/instant-call/host-decline';
  const cancel = '/api/instant-call/cancel';
  const callEnd = '/api/call/Callend';
  const updateCall = '/api/UpdateCall';
  const ack = '/api/call/receiver-ringing-ack';

  Map<String, dynamic> talkNowRing() => ringPush(
    callId: 'sess1',
    extra: const {'isInstantCall': 'true', 'instantCallSessionId': 'sess1'},
  );

  setUpAll(initCallTestEnv);
  setUp(() async {
    final env = await resetCallTestEnv();
    backend = env.backend;
    backend.replies['POST $hostAccept'] = (_) => {
      'success': true,
      'callId': 901,
      'channelName': 'instant_5_1',
      'hostToken': 'tok',
    };
  });
  tearDown(resetCallState);

  group('the ring', () {
    test('a Talk Now ring says so; nothing to ack', () async {
      final p = CallPayload.parse(talkNowRing())!;
      expect(p.session.isInstantCall, isTrue);
      expect(p.session.instantCallSessionId, 'sess1');
      expect(p.session.backendCallId, isNull); // no call record yet

      await CallSignals.onInvite(talkNowRing(), foreground: false);
      await settle(200);
      expect(backend.to('POST', ack), isEmpty);
    });

    test('an end with only the session id stops the ring', () async {
      await CallSignals.onInvite(talkNowRing(), foreground: false);
      expect(calls.value.phase, CallPhase.ringing);
      // The backend's "stop ringing" (caller cancelled, another host took
      // it, the search moved on).
      final end = PushEnvelope.fromMap(const {
        'type': 'CALL_ENDED',
        'instantCallSessionId': 'sess1',
        'dismissNotification': 'true',
      });
      expect(end.callId, 'sess1');
      await CallSignals.onEnded(end.callId!);
      expect(calls.value.phase.isActive, isFalse);
    });
  });

  group('host', () {
    test(
      'accept: host-accept, never UpdateCall; Callend bills the record',
      () async {
        await CallSignals.onInvite(talkNowRing(), foreground: false);
        await CallActions.accept();
        await settle(500);
        expect(backend.lastBody('POST', hostAccept), {'sessionId': 'sess1'});
        expect(backend.to('POST', updateCall), isEmpty);
        expect(calls.value.serverCallId, '901');
        expect(await NativeCallMarks.serverCallId('sess1'), '901');

        // Pushes about the call record match this call.
        expect(calls.value.isSameCall('901'), isTrue);

        calls.setConnected(
          at: DateTime.now().subtract(const Duration(seconds: 30)),
        );
        await CallActions.hangup();
        await settle();
        final body = backend.lastBody('POST', callEnd);
        expect(body['callId'], '901');
        expect(body['status'], 'completed');
        // The host never cancels the caller's search.
        expect(backend.to('POST', cancel), isEmpty);
      },
    );

    test('accept refused (taken, too late): leave, with a word why', () async {
      backend.failures['POST $hostAccept'] = (
        400,
        'You are not currently being rung for this session.',
      );
      await CallSignals.onInvite(talkNowRing(), foreground: false);
      await CallActions.accept();
      await settle(500);
      expect(calls.value.phase.isActive, isFalse);
      expect(alertLog(), contains('toast|${InstantCallErrorKeys.taken}'));
      expect(backend.to('POST', updateCall), isEmpty);
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test(
      'decline: host-decline (the next host rings now), no Callend',
      () async {
        await CallSignals.onInvite(talkNowRing(), foreground: false);
        await CallActions.decline();
        await settle();
        expect(backend.lastBody('POST', hostDecline), {'sessionId': 'sess1'});
        expect(backend.to('POST', callEnd), isEmpty);
      },
    );

    test('hung up before the accept reply: asks again, then bills', () async {
      calls.receive(
        const CallSession(
          callId: 'sess1',
          callerId: '5',
          receiverId: '9',
          isInstantCall: true,
          instantCallSessionId: 'sess1',
        ),
      );
      calls
        ..setAccepted()
        ..setConnected(
          at: DateTime.now().subtract(const Duration(seconds: 10)),
        );
      await CallActions.hangup();
      await settle(100);
      expect(backend.to('POST', hostAccept), hasLength(1));
      expect(backend.lastBody('POST', callEnd)['callId'], '901');
    });

    test('background notification Decline / Hang up', () async {
      await HeadlessCallEnd.decline('sess1', talkNowRing());
      expect(backend.lastBody('POST', hostDecline), {'sessionId': 'sess1'});

      await NativeCallMarks.saveServerCallId('sess2', '902');
      await NativeCallMarks.markConnected(
        'sess2',
        DateTime.now().subtract(const Duration(seconds: 20)),
      );
      await HeadlessCallEnd.hangUp('sess2', {
        'callId': 'sess2',
        '__role': 'receiver',
        'receiverId': '9',
        'isInstantCall': 'true',
        'instantCallSessionId': 'sess2',
      });
      expect(backend.lastBody('POST', callEnd)['callId'], '902');
    });
  });

  group('caller', () {
    CallSession searching() => const CallSession(
      callId: 'sess1',
      callDocumentId: 'sess1',
      callerId: '9',
      isInstantCall: true,
      instantCallSessionId: 'sess1',
    );

    test(
      'connected: keeps the call record; a late "failed" is ignored',
      () async {
        calls.startOutgoing(searching());
        CallSignals.onInstantCallConnected(const {
          'instantCallSessionId': 'sess1',
          'callId': '901',
          'hostUserId': '70',
          'hostName': 'Meera',
        });
        expect(calls.value.serverCallId, '901');
        expect(calls.value.receiverId, '70');

        calls.setConnected();
        CallSignals.onInstantCallFailed(const {
          'instantCallSessionId': 'sess1',
          'reason': 'timeout',
        });
        expect(calls.value.phase, CallPhase.ongoing);

        await CallActions.hangup();
        await settle();
        expect(backend.lastBody('POST', callEnd)['callId'], '901');
      },
    );

    test('hang up while searching: cancel the search, no Callend', () async {
      calls.startOutgoing(searching());
      await CallActions.hangup();
      await settle(100);
      expect(backend.lastBody('POST', cancel), {'sessionId': 'sess1'});
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('the search failed: the call ends', () async {
      calls.startOutgoing(searching());
      CallSignals.onInstantCallFailed(const {
        'instantCallSessionId': 'sess1',
        'reason': 'pool_exhausted',
      });
      expect(calls.value.phase.isActive, isFalse);
    });
  });

  test("the search reply carries the caller's Talk Now rate", () {
    final r = InitiatedInstantCall.tryParse(const {
      'success': true,
      'sessionId': 'sess1',
      'callerToken': 'tok',
      'channelName': 'instant_9_1',
      'callerRate': 12,
    })!;
    expect(r.callerRate, 12);
  });

  test('Callend id: the record for Talk Now, the call otherwise', () {
    const talk = CallSession(callId: 'sess1', isInstantCall: true);
    expect(talk.backendCallId, isNull);
    expect(talk.copyWith(serverCallId: '901').backendCallId, '901');
    expect(const CallSession(callId: '42').backendCallId, '42');
    final input = EndFlow.endInput(
      talk.copyWith(serverCallId: '901', role: CallRole.receiver),
      connected: true,
      seconds: 5,
    );
    expect(input.callId, '901');
  });
}
