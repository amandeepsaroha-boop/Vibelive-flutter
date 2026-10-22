import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/callscreen/pending_decline_queue.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/callscreen/helper/call_actions.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_navigator.dart';
import 'package:vibelive/app/callscreen/helper/call_permissions.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/call_timers.dart';
import 'package:vibelive/app/callscreen/helper/flows/outgoing_flow.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';

import 'logic_fakes.dart';

const initiate = '/api/initiateCall';
const callEnd = '/api/call/Callend';
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

void main() {
  final calls = CallController.instance;
  late FakeBackend backend;
  late FakeRingtone ringtone;
  late FakePermissions permissions;
  late FakeRtcEngine Function() engine;

  setUpAll(initCallTestEnv);
  setUp(() async {
    final env = await resetCallTestEnv();
    backend = env.backend;
    ringtone = env.ringtone;
    permissions = env.permissions;
    engine = env.engine;
  });
  tearDown(resetCallState);

  group('outgoing', () {
    test('success: RN body, caller session, joined while ringing', () async {
      backend.replies['POST $initiate'] = (_) => started();
      final ok = await OutgoingFlow.place(
        OutgoingRequest.fromHost(host(), video: true),
      );
      expect(ok, isTrue);
      final body = backend.lastBody('POST', initiate);
      expect(body['callerId'], 9);
      expect(body['receiverId'], 70);
      expect(body['type'], 'videoCall');
      expect(body['role'], 'Client');
      expect(body['categoryId'], 'dcybx2ez5hjaqshrfpqg39on');
      expect(body['userPlatform'], isNotEmpty);

      final s = calls.value;
      expect(s.phase, CallPhase.calling);
      expect(s.role, CallRole.caller);
      expect(s.callId, '501');
      expect(s.callDocumentId, 'call-doc');
      expect(s.isVideo, isTrue);
      expect(s.remote.id, '70');
      expect(s.remote.documentId, 'usr7');
      expect(s.receiverDocId, 'exp7');
      expect(s.callerDocId, 'u9');
      expect(s.localUid, 9);
      expect(CallNavigator.debugPending, AppRoutes.call);
      expect(CallTimers.instance.isArmed(CallTimers.noAnswer), isTrue);

      await settle(500); // cold-boot settle before the join
      final rtc = engine();
      expect(rtc.calls, contains('joinChannel:call_9_70_1:9'));
      final options = rtc.joins.single;
      expect(
        options.channelProfile,
        ChannelProfileType.channelProfileCommunication,
      );
      expect(options.clientRoleType, ClientRoleType.clientRoleBroadcaster);
      expect(options.publishCameraTrack, isTrue);
      expect(rtc.appId, 'abcdefabcdefabcdefabcdefabcdef12', reason: 'token');
      expect(ringtone.log, contains('start:ringback'));
    });

    test('busy: RN alert, no call, never a Callend (E-82)', () async {
      backend.replies['POST $initiate'] = (_) => {
        'status': 'busy',
        'message': 'Receiver is currently on another call',
        'call': {'id': 3},
      };
      final ok = await OutgoingFlow.place(
        OutgoingRequest.fromHost(host(), video: false),
      );
      expect(ok, isFalse);
      expect(calls.value.phase, CallPhase.idle);
      expect(
        alertLog(),
        contains('callflow:errors.busy_title|call:errors.user_busy'),
      );
      await settle();
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('invalid answer and failures: "Call failed"', () async {
      backend.replies['POST $initiate'] = (_) => {'channelName': 'c'};
      await OutgoingFlow.place(OutgoingRequest.fromHost(host(), video: false));
      expect(
        alertLog(),
        contains('callflow:errors.failed_title|call:errors.invalid_response'),
      );
      backend.failures['POST $initiate'] = (
        400,
        'Platform is under maintenance',
      );
      await OutgoingFlow.place(OutgoingRequest.fromHost(host(), video: false));
      expect(
        alertLog().last,
        'callflow:errors.failed_title|call:errors.initiate_failed',
      );
      expect(calls.value.phase, CallPhase.idle);
    });

    test('permission blocked: Settings alert, nothing sent', () async {
      permissions.check_ = CallAccess.blocked;
      await OutgoingFlow.place(OutgoingRequest.fromHost(host(), video: true));
      expect(
        alertLog(),
        contains(
          'callflow:permission.mic_camera_title|'
          'callflow:permission.mic_camera_blocked',
        ),
      );
      expect(backend.to('POST', initiate), isEmpty);

      // Denied → asked → granted: the call goes ahead.
      permissions
        ..check_ = CallAccess.denied
        ..afterRequest = CallAccess.granted;
      backend.replies['POST $initiate'] = (_) => started();
      expect(
        await OutgoingFlow.place(
          OutgoingRequest.fromHost(host(), video: false),
        ),
        isTrue,
      );
      expect(permissions.requests, 1);
    });

    test('callback / redial target, missing ids → "Unable"', () async {
      await OutgoingFlow.place(
        OutgoingRequest.fromTarget(
          const CallTarget(receiverId: ''),
          video: false,
        ),
      );
      expect(
        alertLog(),
        contains(
          'callflow:errors.unable_title|call:errors.missing_participants',
        ),
      );
      backend.replies['POST $initiate'] = (_) => started();
      await OutgoingFlow.place(
        OutgoingRequest.fromTarget(
          const CallTarget(receiverId: '70', categoryId: '12'),
          video: false,
        ),
      );
      expect(backend.lastBody('POST', initiate)['categoryId'], '12');
    });
  });

  group('incoming', () {
    test('accept: UpdateCall with the device, join, /call', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallActions.accept();
      expect(calls.value.phase, CallPhase.accepted);
      expect(CallNavigator.debugPending, AppRoutes.call);
      await settle(500);
      expect(backend.lastBody('POST', updateCall), {
        'callId': '42',
        'callerId': '5',
        'receiverId': '9',
        'status': 'ongoing',
        'type': 'voiceCall',
        'answeredDeviceId': 'ios-device-1',
      });
      expect(engine().calls, contains('joinChannel:call_5_9_1:9'));
      expect(ringtone.log, contains('stop'));
    });

    test('decline: idle first, then the RN body', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallActions.decline();
      expect(calls.value.phase, CallPhase.idle);
      await settle();
      final sent = backend.to('POST', callEnd).single;
      expect(sent.o.headers['x-idempotency-key'], 'callend:42');
      final body = Map<String, dynamic>.from(sent.body! as Map);
      expect(body['callId'], '42');
      expect(body['status'], 'declined');
      expect(body['endedById'], 9);
      expect(body['duration'], 0);
      expect(body['totalCost'], 0);
      expect(body['type'], 'voiceCall');
      expect(body['calleridDocID'], 'caller-doc');
    });

    test('decline of a ghost ring sends nothing (E-15)', () async {
      calls.receive(
        CallSession(
          callId: '42',
          callerId: '5',
          receiverId: '9',
          sentAt: DateTime.now().subtract(const Duration(minutes: 3)),
        ),
      );
      await CallActions.decline();
      await settle();
      expect(backend.to('POST', callEnd), isEmpty);
    });

    test('a failed decline is queued for replay (E-27)', () async {
      backend.failures['POST $callEnd'] = (500, 'boom');
      await CallSignals.onInvite(ringPush(), foreground: false);
      await CallActions.decline();
      await settle(50);
      expect(PendingDeclineQueue.pending.map((d) => d.callId), ['42']);
    });

    test('decline and block', () async {
      await CallSignals.onInvite(ringPush(), foreground: false);
      expect(await CallActions.declineAndBlock(), isTrue);
      expect(backend.lastBody('POST', '/api/user-blocks'), {
        'targetUserId': 'caller-doc',
        'reason': 'Blocked from an incoming call.',
      });
      await CallSignals.onInvite(ringPush(callId: '43'), foreground: false);
      expect(await CallActions.declineAndReport(), isTrue);
      final report = backend.lastBody('POST', '/api/reports')['data'] as Map;
      expect(report['note'], 'Reported from an incoming call.');
      expect(report['reported_by_user'], 'u9');
      expect(report['reported_to_user'], 'caller-doc');
    });
  });

  group('hangup (decision 9)', () {
    test('connected: completed with the wall-clock duration', () async {
      calls.receive(
        const CallSession(callId: '42', callerId: '5', receiverId: '9'),
      );
      calls
        ..setAccepted()
        ..setConnected(
          at: DateTime.now().subtract(const Duration(seconds: 75)),
        );
      await CallActions.hangup();
      await CallActions.hangup(); // idempotent
      await settle();
      final body = backend.to('POST', callEnd).single.body! as Map;
      expect(body['status'], 'completed');
      expect(body['duration'], greaterThanOrEqualTo(75));
      expect(body['endedById'], 9);
    });

    test('caller cancel before connect: no status (E-92)', () async {
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
      await CallActions.hangup();
      await settle();
      final body = backend.lastBody('POST', callEnd);
      expect(body.containsKey('status'), isFalse);
      expect(body['endedById'], 9);
      expect(body['duration'], 0);
    });

    test('receiver that never connected: declined', () async {
      calls.receive(
        const CallSession(callId: '42', callerId: '5', receiverId: '9'),
      );
      calls.setAccepted();
      await CallActions.hangup();
      await settle();
      expect(backend.lastBody('POST', callEnd)['status'], 'declined');
    });

    test('endedById falls back to the call when signed out', () async {
      calls.receive(
        const CallSession(callId: '42', callerId: '5', receiverId: '31'),
      );
      calls.setAccepted();
      final s = calls.value;
      // A cold-start accept can run before the session user is known.
      SessionStore.instance.value = const SessionState(
        user: {'documentId': 'u9'},
      );
      await CallActions.hangup();
      await settle();
      expect(s.receiverId, '31');
      expect(backend.lastBody('POST', callEnd)['endedById'], 31);
    });

    test('lost the race against the other side: swallowed', () async {
      backend.failures['POST $callEnd'] = (400, 'Call has been Ended already');
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
      await CallActions.hangup();
      await settle();
      expect(calls.value.phase.isActive, isFalse);
    });

    test('afterEnded: caller + connected → feedback', () {
      calls.startOutgoing(
        const CallSession(callId: '77', callerId: '9', receiverId: '5'),
      );
      calls
        ..setAccepted()
        ..setConnected()
        ..end();
      expect(CallActions.afterEnded(), PostCallStep.feedback);
      calls.reset();
      calls.receive(
        const CallSession(callId: '42', callerId: '5', receiverId: '9'),
      );
      calls
        ..setAccepted()
        ..setConnected()
        ..end();
      expect(CallActions.afterEnded(), PostCallStep.exit);
    });
  });
}
