import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/callscreen/pending_decline_queue.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/authscreen/helper/deep_links.dart';
import 'package:vibelive/app/callscreen/helper/call_actions.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_device.dart';
import 'package:vibelive/app/callscreen/helper/call_permissions.dart';
import 'package:vibelive/app/callscreen/helper/call_runtime.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/call_timers.dart';
import 'package:vibelive/app/callscreen/helper/engine/call_engine.dart';
import 'package:vibelive/app/callscreen/helper/flows/end_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/incoming_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/native_flow.dart';
import 'package:vibelive/app/callscreen/helper/flows/outgoing_flow.dart';

import 'logic_fakes.dart';

const ack = '/api/call/receiver-ringing-ack';
const callEnd = '/api/call/Callend';
const initiate = '/api/initiateCall';
const updateCall = '/api/UpdateCall';

/// An `/expert-profiles` row (user 70 `usr7`, expert `exp7`).
HostCard host() => HostCard.fromJson(const {
  'id': 7,
  'documentId': 'exp7',
  'rates': {'videoCallRate': 30, 'voiceCallRate': 20},
  'user': {'id': 70, 'documentId': 'usr7', 'name': 'Meera'},
});

Map<String, dynamic> started({String id = '501'}) => {
  'channelName': 'call_9_70_1',
  'callerToken': agoraToken(),
  'receiverToken': 'rt',
  'callerId': 9,
  'callDetails': {'id': int.parse(id), 'documentId': 'call-doc'},
  'receiverDocId': 'exp7',
};

/// Review findings fixed in the call logic (U*, A*, I* ids).
void main() {
  final calls = CallController.instance;
  late FakeBackend backend;
  late FakeRingtone ringtone;
  late FakePermissions permissions;
  late FakePlatform platform;
  late FakeRtcEngine Function() engine;

  setUpAll(initCallTestEnv);
  setUp(() async {
    final env = await resetCallTestEnv();
    backend = env.backend;
    ringtone = env.ringtone;
    permissions = env.permissions;
    platform = env.platform;
    engine = env.engine;
  });
  tearDown(resetCallState);

  /// A receiver call answered and connected (no engine involved).
  void connectedReceiver({DateTime? at}) {
    calls.receive(
      const CallSession(callId: '42', callerId: '5', receiverId: '9'),
    );
    calls
      ..setAccepted()
      ..setConnected(at: at);
  }

  group('accept permission gate (A2)', () {
    test('denied: keeps ringing, nothing billed or joined', () async {
      permissions
        ..check_ = CallAccess.denied
        ..afterRequest = CallAccess.denied;
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallActions.accept();
      expect(permissions.requests, 1);
      expect(calls.value.phase, CallPhase.ringing);
      expect(alertLog(), isNotEmpty, reason: 'the RN permission alert');
      expect(CallTimers.instance.isArmed(CallTimers.incomingRing), isTrue);
      await settle(50);
      expect(backend.to('POST', updateCall), isEmpty);
      expect(ringtone.log, isNot(contains('stop')), reason: 'still rings');
    });

    test('granted on the prompt: accepted and billed', () async {
      permissions
        ..check_ = CallAccess.denied
        ..afterRequest = CallAccess.granted;
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallActions.accept();
      expect(calls.value.phase, CallPhase.accepted);
      await settle(50);
      expect(backend.to('POST', updateCall), hasLength(1));
    });

    test('a system-UI accept asks once, on the first resume', () async {
      permissions
        ..check_ = CallAccess.denied
        ..afterRequest = CallAccess.granted;
      await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
      expect(permissions.requests, 0, reason: 'app in the background');
      CallDevice.debugForeground = true;
      await CallSignals.onAppResumed();
      await settle();
      expect(permissions.requests, 1);
      await CallSignals.onAppResumed();
      await settle();
      expect(permissions.requests, 1, reason: 'once per call');
    });
  });

  group('hangup', () {
    test('in the 500 ms connect window: connected summary + completed '
        '(U13)', () async {
      calls.startOutgoing(
        CallSession(
          callId: '77',
          channelName: 'call_9_5_1',
          token: agoraToken(),
          callerId: '9',
          receiverId: '5',
        ),
      );
      await CallEngine.instance.join(
        channel: 'call_9_5_1',
        token: agoraToken(),
        uid: 9,
        video: false,
      );
      engine()
        ..joined('call_9_5_1', 9)
        ..remoteJoined(5);
      await settle();
      expect(CallTimers.instance.isArmed(CallTimers.callerConnect), isTrue);
      expect(calls.value.connectedAt, isNull);
      await CallActions.hangup();
      final ended = calls.value.callId != null
          ? calls.value
          : CallRuntime.lastCall;
      expect(ended.connectedAt, isNotNull);
      expect(CallActions.afterEnded(), PostCallStep.feedback);
      await settle();
      final body = backend.lastBody('POST', callEnd);
      expect(body['status'], 'completed');
      expect(body['duration'], greaterThanOrEqualTo(1));
    });

    test('a failed Callend is queued for replay (A12)', () async {
      backend.failures['POST $callEnd'] = (500, 'boom');
      connectedReceiver(
        at: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await CallActions.hangup();
      await settle(50);
      final queued = PendingDeclineQueue.pending.single;
      expect(queued.callId, '42');
      expect(queued.body['status'], 'completed');
    });

    test('a lost race is not queued', () async {
      backend.failures['POST $callEnd'] = (400, 'Call has been Ended already');
      connectedReceiver();
      await CallActions.hangup();
      await settle(50);
      expect(PendingDeclineQueue.pending, isEmpty);
    });

    test('a replay drops "already ended" answers', () async {
      connectedReceiver();
      backend.failures['POST $callEnd'] = (500, 'boom');
      await CallActions.hangup();
      await settle(50);
      backend.failures['POST $callEnd'] = (409, 'Call already ended');
      await PendingDeclineQueue.flush();
      expect(PendingDeclineQueue.pending, isEmpty);
    });
  });

  group('sign-out (U3)', () {
    test('a live call: Callend sent before it returns, call cleared', () async {
      connectedReceiver();
      await CallActions.endForSignOut();
      expect(backend.to('POST', callEnd), hasLength(1));
      expect(backend.lastBody('POST', callEnd)['status'], 'completed');
      expect(calls.value.phase, CallPhase.idle);
    });

    test('a ring is declined', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallActions.endForSignOut();
      expect(backend.lastBody('POST', callEnd)['status'], 'declined');
      expect(calls.value.phase, CallPhase.idle);
    });

    test('no call: nothing sent', () async {
      await CallActions.endForSignOut();
      expect(backend.sent, isEmpty);
    });
  });

  group('outgoing', () {
    test('place refuses while a call is in progress (U5)', () async {
      backend.replies['POST $initiate'] = (_) => started();
      connectedReceiver();
      final ok = await OutgoingFlow.place(
        OutgoingRequest.fromHost(host(), video: false),
      );
      expect(ok, isFalse);
      expect(backend.to('POST', initiate), isEmpty);
      expect(calls.value.callId, '42');
    });

    test('an ended summary is finished first, then the call is placed; '
        'the old screen exit is ignored (U5)', () async {
      backend.replies['POST $initiate'] = (_) => started();
      calls.debugSet(
        const CallSession(
          phase: CallPhase.ended,
          role: CallRole.caller,
          callId: '77',
        ),
      );
      final ok = await OutgoingFlow.place(
        OutgoingRequest.fromHost(host(), video: false),
      );
      expect(ok, isTrue);
      expect(calls.value.callId, '501');
      // The previous call's post-call runner fires late: nothing happens.
      CallActions.exitToHome(callId: '77');
      expect(calls.value.callId, '501');
      expect(calls.value.phase, CallPhase.calling);
    });

    test('the Android ongoing service starts with the call (A10)', () async {
      backend.replies['POST $initiate'] = (_) => started();
      await OutgoingFlow.place(OutgoingRequest.fromHost(host(), video: false));
      await settle();
      expect(platform.log, contains('outgoing:501'));
    });

    test(
      'a callback target rate caps the call without a lookup (A11)',
      () async {
        backend
          ..cash = 100
          ..replies['POST $initiate'] = (_) => started();
        await OutgoingFlow.place(
          OutgoingRequest.fromTarget(
            const CallTarget(
              receiverId: '70',
              receiverDocId: 'usr7',
              ratePerMin: 10,
            ),
            video: false,
          ),
        );
        calls
          ..setAccepted()
          ..setConnected();
        await settle(80);
        expect(CallTimers.instance.isArmed(CallTimers.maxDuration), isTrue);
        expect(backend.to('GET', '/api/expert-profiles'), isEmpty);
      },
    );

    test('caller exit: Discover re-opens the host USER (U9)', () async {
      String? askedExpert;
      EndFlow.hostLookup = ({expertDocumentId, userId}) async {
        askedExpert = expertDocumentId;
        return host();
      };
      calls.startOutgoing(
        const CallSession(
          callId: '77',
          callerId: '9',
          receiverId: '70',
          receiverDocId: 'exp7', // expert-profile id: never opened as is
          remote: CallPeer(id: '70'),
        ),
      );
      calls.end();
      CallActions.exitToHome(callId: '77');
      await settle(450);
      expect(askedExpert, 'exp7');
      expect(DeepLinks.instance.takeOpenUser(), 'usr7');
    });
  });

  group('invites', () {
    test('foreground VoIP lives 120 s, background VoIP 45 s (I3)', () async {
      final presenting = CallSignals.onInvite(
        ringPush(sentAt: DateTime.now().subtract(const Duration(seconds: 60))),
        foreground: true,
        source: CallPushSource.voip,
      );
      await settle(30);
      expect(calls.value.phase, CallPhase.ringing);
      await presenting;

      resetCallState();
      await CallSignals.onInvite(
        ringPush(
          callId: '43',
          sentAt: DateTime.now().subtract(const Duration(seconds: 130)),
        ),
        foreground: true,
        source: CallPushSource.voip,
      );
      expect(calls.value.phase, CallPhase.idle);
    });

    test('a native ringer already up: no in-app ring (I2)', () async {
      platform.nativeRinging.add('42');
      final presenting = CallSignals.onInvite(ringPush(), foreground: true);
      await settle(50);
      expect(calls.value.phase, CallPhase.ringing);
      expect(ringtone.log, isNot(contains('start:incoming')));
      expect(IncomingFlow.isMarkedNativeRinging('42'), isTrue);
      await presenting;
    });

    test('a notification-body tap rings in-app, no second ack (A8)', () async {
      final presenting = CallSignals.onInvite(
        ringPush(),
        foreground: true,
        source: CallPushSource.notificationTap,
      );
      await settle(50);
      expect(ringtone.log, contains('start:incoming'));
      expect(backend.to('POST', ack), isEmpty);
      await presenting;
    });

    test('the raw payload of the ringing call is kept (I4)', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      expect(CallRuntime.ringingPayload?['callId'], '42');
      expect(CallRuntime.ringingPayload?['channelName'], 'call_5_9_1');
      CallSignals.onAnsweredElsewhere('42');
      expect(CallRuntime.ringingPayload, isNull);
    });

    test('openedLocked is set when locked (A9)', () async {
      platform.locked = true;
      await CallSignals.onInvite(ringPush(), foreground: false);
      await settle();
      expect(calls.value.openedLocked, isTrue);
    });

    test('a background isolate never arms the ring timeout (A1)', () async {
      CallRuntime.isUiIsolate = false;
      await CallSignals.onInvite(ringPush(), foreground: false);
      expect(calls.value.phase, CallPhase.ringing);
      expect(CallTimers.instance.isArmed(CallTimers.incomingRing), isFalse);
    });

    test('decline-and-block after the ring ended still blocks (U2)', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      final captured = calls.value;
      await CallSignals.onEnded('42'); // the caller gave up mid-confirm
      expect(calls.value.phase, CallPhase.idle);
      expect(await CallActions.declineAndBlock(call: captured), isTrue);
      expect(
        backend.lastBody('POST', '/api/user-blocks')['targetUserId'],
        'caller-doc',
      );
      // Without the snapshot: the ring that just went away.
      expect(await CallActions.declineAndReport(), isTrue);
      await settle();
      expect(backend.to('POST', callEnd), isEmpty, reason: 'no decline');
    });
  });

  group('native', () {
    test('a failed native UpdateCall is sent again (I1)', () async {
      await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
      await settle(50);
      expect(backend.to('POST', updateCall), isEmpty);
      await CallSignals.onNativeUpdateFailed('42');
      final body = backend.lastBody('POST', updateCall);
      expect(body['callId'], '42');
      expect(body['status'], 'ongoing');
      expect(body['answeredDeviceId'], 'ios-device-1');
      expect(body.containsKey('startTime'), isFalse, reason: 'server clock');
    });

    test('…retried while it fails, until it goes through (I1)', () async {
      NativeFlow.updateRetryDelays = const [Duration(milliseconds: 120)];
      backend.failures['POST $updateCall'] = (500, 'boom');
      await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
      final retrying = CallSignals.onNativeUpdateFailed('42');
      await settle(40);
      expect(backend.to('POST', updateCall), hasLength(1));
      backend.failures.remove('POST $updateCall');
      await retrying;
      expect(backend.to('POST', updateCall), hasLength(2));
    });

    test(
      'in-app accept of a CallKit ring: native sends UpdateCall (I6)',
      () async {
        CallDevice.debugIsIOS = true;
        platform.nativeRinging.add('42');
        await CallSignals.onInvite(ringPush(), foreground: false);
        await CallActions.accept();
        await settle(50);
        expect(platform.log, contains('answer:42'));
        expect(backend.to('POST', updateCall), isEmpty);
      },
    );

    test('same uid joined elsewhere: ended locally, no API (A7)', () async {
      await CallSignals.onNativeAccepted(ringPush(), apiDone: true);
      await settle(500);
      final rtc = engine()..joined('call_5_9_1', 9);
      rtc.connection(
        ConnectionStateType.connectionStateFailed,
        ConnectionChangedReasonType.connectionChangedSameUidLogin,
      );
      await settle();
      expect(calls.value.phase.isActive, isFalse);
      expect(backend.to('POST', callEnd), isEmpty);
    });
  });

  test('phaseSince is stamped on calling / ringing / accepted / ongoing '
      '(U10)', () {
    final t0 = DateTime(2026, 1, 1, 10);
    DateTime at(int s) => t0.add(Duration(seconds: s));
    void run(int s, void Function() body) =>
        withClock(Clock.fixed(at(s)), body);

    run(0, () {
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
    });
    expect(calls.value.phaseSince, at(0));
    run(4, calls.setRinging);
    expect(calls.value.phaseSince, at(4));
    run(9, calls.setAccepted);
    expect(calls.value.phaseSince, at(9));
    run(12, calls.setConnected);
    expect(calls.value.phaseSince, at(12));
    run(20, () => calls.update((c) => c.copyWith(categoryName: 'x')));
    expect(calls.value.phaseSince, at(12), reason: 'same phase');
    run(30, calls.end);
    expect(calls.value.phaseSince, at(12), reason: 'ended is not stamped');

    calls.reset();
    expect(calls.value.phaseSince, isNull);
    run(40, () {
      calls.receive(
        const CallSession(callId: '42', callerId: '5', receiverId: '9'),
      );
    });
    expect(calls.value.phaseSince, at(40));
    run(50, () {
      calls.receive(
        const CallSession(callId: '43', callerId: '6', receiverId: '9'),
      );
    });
    expect(calls.value.phaseSince, at(50), reason: 'a new ring');
  });
}
