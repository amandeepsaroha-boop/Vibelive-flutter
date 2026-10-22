import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_device.dart';
import 'package:vibelive/app/callscreen/helper/call_navigator.dart';
import 'package:vibelive/app/callscreen/helper/call_payload.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/engine/call_engine.dart';
import 'package:vibelive/app/callscreen/helper/native/callkit_params.dart';
import 'package:vibelive/app/callscreen/helper/native/native_call_events.dart';
import 'package:vibelive/core/config/env.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'logic_fakes.dart';

const updateCall = '/api/UpdateCall';

/// Android, app killed, call accepted from the plugin's notification: the
/// UI isolate boots and sees the accept 2-3 times (plugin `activeCalls`
/// accepted, the background isolate's pending accept, maybe the live
/// ACCEPT event). It must reach `/call` and join Agora once, as the
/// receiver, with the ring's channel and token.
void main() {
  final calls = CallController.instance;
  late FakeBackend backend;
  late FakePlatform platform;
  late FakeRtcEngine Function() engine;

  const channel = 'call_5_9_1';

  setUpAll(initCallTestEnv);
  setUp(() async {
    final env = await resetCallTestEnv();
    backend = env.backend;
    platform = env.platform;
    engine = env.engine;
  });
  tearDown(resetCallState);

  /// What the plugin stored for the ring (and hands back in `activeCalls`
  /// and the ACCEPT event): our params' `extra`.
  Map<String, dynamic> pluginExtra([Map<String, dynamic> extra = const {}]) =>
      CallKitParamsBuilder.incoming(
        ringPush(extra: extra),
        callId: '42',
        ring: const Duration(seconds: 30),
      ).extra!;

  void expectJoinedOnce({String token = ''}) {
    final joins = engine().calls.where((c) => c.startsWith('joinChannel'));
    expect(joins, ['joinChannel:$channel:9'], reason: 'one join, uid 9');
    expect(engine().tokens, [token.isEmpty ? agoraToken() : token]);
  }

  group('killed-state accept (Android)', () {
    test('activeCalls + pending accept together: /call, one join', () async {
      // The background isolate saved the accept; the plugin also lists it
      // as accepted. Both replay at boot, the second while the first join
      // is still creating the engine (this used to cancel the join).
      await CallSignals.savePendingAccept(pluginExtra(), apiDone: false);
      final fromPlugin = CallSignals.onColdStartAccept(
        pluginExtra(),
        apiDone: false,
      );
      final fromStore = CallSignals.reconcile();
      await Future.wait([fromPlugin, fromStore]);
      await settle(600); // engine init + the cold-boot settle (E-55)

      final s = calls.value;
      expect(s.phase, CallPhase.accepted);
      expect(s.callId, '42');
      expect(s.isReceiver, isTrue);
      expect(CallNavigator.debugPending, AppRoutes.call);
      expectJoinedOnce();
      // Audio only until the app is in front.
      expect(engine().joins.single.publishCameraTrack, isFalse);
      // One UpdateCall, with this device (it reached the caller).
      expect(backend.to('POST', updateCall), hasLength(1));
      expect(backend.lastBody('POST', updateCall)['receiverId'], '9');
    });

    test('plugin activeCalls through NativeCallEvents.reconcile', () async {
      final params = CallKitParamsBuilder.incoming(
        ringPush(),
        callId: '42',
        ring: const Duration(seconds: 30),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const pluginChannel = MethodChannel('flutter_callkit_incoming');
      messenger.setMockMethodCallHandler(pluginChannel, (call) async {
        if (call.method != 'activeCalls') return null;
        // As the plugin's JSON store returns it (extra survives).
        return [
          jsonDecode(
            jsonEncode({
              'id': params.id,
              'nameCaller': params.nameCaller,
              'avatar': params.avatar,
              'type': params.type,
              'extra': params.extra,
              'isAccepted': true,
            }),
          ),
        ];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(pluginChannel, null),
      );

      await NativeCallEvents.reconcile();
      await settle(600);

      expect(calls.value.phase, CallPhase.accepted);
      expect(
        calls.value.remote.avatarUrl,
        '${Env.apiBaseUrl}/uploads/ravi.png',
      );
      expect(CallNavigator.debugPending, AppRoutes.call);
      expectJoinedOnce();
    });

    test('/call is up before the server status check answers', () async {
      // A slow status check (the 2 s race) must not hold the splash.
      backend.replies['GET /api/calls'] = (_) => {'data': <Object>[]};
      final accept = CallSignals.onColdStartAccept(
        pluginExtra(),
        apiDone: false,
      );
      // Synchronous part ran: the call is accepted and /call parked.
      expect(calls.value.phase, CallPhase.accepted);
      expect(CallNavigator.debugPending, AppRoutes.call);
      await accept;
      await settle(600);
      expectJoinedOnce();
    });

    test('closed on the server after /call went up: back to idle', () async {
      backend.replies['GET /api/calls'] = (_) => {
        'data': [
          {'id': 42, 'callStatus': 'missed'},
        ],
      };
      await CallSignals.onColdStartAccept(pluginExtra(), apiDone: false);
      await settle(400);
      expect(calls.value.phase, CallPhase.idle);
      expect(platform.log, contains('end:42'));
      expect(backend.to('POST', updateCall), isEmpty);
      expect(engine, throwsA(anything), reason: 'engine never created');
    });

    test('an accept older than 5 min is dropped (stale TTL)', () async {
      final old = DateTime.now().subtract(const Duration(minutes: 6));
      await CallSignals.onColdStartAccept(
        CallKitParamsBuilder.incoming(
          ringPush(sentAt: old),
          callId: '42',
          ring: const Duration(seconds: 30),
        ).extra!,
        apiDone: false,
      );
      expect(calls.value.phase, CallPhase.idle);
      expect(CallNavigator.debugPending, isNull);
    });

    test('a "+" turned into a space is repaired before the join', () async {
      final token = agoraToken().replaceRange(40, 41, '+');
      await CallSignals.onColdStartAccept(
        pluginExtra({'token': token.replaceAll('+', ' ')}),
        apiDone: false,
      );
      await settle(600);
      expectJoinedOnce(token: token);
    });

    test(
      'video: resume during the join adds the camera, never cancels it',
      () async {
        final accept = CallSignals.onColdStartAccept(
          pluginExtra({'type': 'videoCall'}),
          apiDone: false,
        );
        await accept;
        // The activity comes to the front while the join is in flight.
        CallDevice.debugForeground = true;
        await CallSignals.onAppResumed();
        await settle(600);
        expectJoinedOnce();
        expect(calls.value.isVideo, isTrue);
        expect(engine().calls, contains('startPreview'));
      },
    );

    test('the live ACCEPT event after a reconcile joins once', () async {
      await CallSignals.onColdStartAccept(pluginExtra(), apiDone: false);
      await CallSignals.onNativeAccepted(pluginExtra());
      await settle(600);
      expectJoinedOnce();
      expect(backend.to('POST', updateCall), hasLength(1));
    });
  });

  group('engine join generation', () {
    test('an equal join while the first is in flight keeps it', () async {
      final first = CallEngine.instance.join(
        channel: channel,
        token: agoraToken(),
        uid: 9,
        video: false,
        headless: true,
      );
      final second = CallEngine.instance.join(
        channel: channel,
        token: agoraToken(),
        uid: 9,
        video: false,
      );
      expect(await second, isTrue);
      expect(await first, isTrue);
      expectJoinedOnce();
    });

    test('a leave during the join cancels it', () async {
      final join = CallEngine.instance.join(
        channel: channel,
        token: agoraToken(),
        uid: 9,
        video: false,
      );
      await CallEngine.instance.leave();
      expect(await join, isFalse);
      expect(engine().calls.where((c) => c.startsWith('joinChannel')), isEmpty);
    });
  });

  group('caller avatar', () {
    test('normalised to an absolute URL', () {
      final base = Env.apiBaseUrl;
      expect(CallPayload.absoluteUrl('/uploads/x.jpg'), '$base/uploads/x.jpg');
      expect(CallPayload.absoluteUrl('uploads/x.jpg'), '$base/uploads/x.jpg');
      expect(
        CallPayload.absoluteUrl('https://cdn.test/x.jpg'),
        'https://cdn.test/x.jpg',
      );
      expect(
        CallPayload.absoluteUrl('//cdn.test/x.jpg'),
        'https://cdn.test/x.jpg',
      );
      expect(
        CallPayload.absoluteUrl('{"url":"/uploads/y.png"}'),
        '$base/uploads/y.png',
      );
      expect(
        CallPayload.absoluteUrl({
          'data': {
            'attributes': {
              'formats': {
                'small': {'url': '/uploads/s.png'},
              },
            },
          },
        }),
        '$base/uploads/s.png',
      );
      for (final none in [null, '', '  ', 'null', 'Null', 'undefined', '{']) {
        expect(CallPayload.absoluteUrl(none), isNull, reason: '$none');
      }
    });

    test('ring → plugin avatar, extra round-trip and the session', () {
      final params = CallKitParamsBuilder.incoming(
        ringPush(),
        callId: '42',
        ring: const Duration(seconds: 30),
      );
      final url = '${Env.apiBaseUrl}/uploads/ravi.png';
      // The plugin can only load http(s): never the raw relative path.
      expect(params.avatar, url);
      expect(params.nameCaller, 'Ravi Kumar');
      // The accept event / activeCalls hand `extra` back: still complete.
      final extra = jsonDecode(jsonEncode(params.extra)) as Map;
      expect(extra['ProfilePic'], '/uploads/ravi.png');
      final session = CallPayload.parse(extra, selfId: '9')!.session;
      expect(session.remote.avatarUrl, url);
      expect(session.remote.name, 'Ravi Kumar');
      expect(session.channelName, channel);
      expect(session.token, agoraToken());
      expect(session.localUid, 9);
    });

    test('a full URL and the ongoing notification', () {
      final params = CallKitParamsBuilder.incoming(
        ringPush(extra: {'ProfilePic': 'https://cdn.test/p.png'}),
        callId: '42',
        ring: const Duration(seconds: 30),
      );
      expect(params.avatar, 'https://cdn.test/p.png');
      final ongoing = CallKitParamsBuilder.ongoing(
        '42',
        name: 'Ravi',
        video: false,
        extra: {'ProfilePic': '/uploads/r.png'},
      );
      expect(ongoing.avatar, '${Env.apiBaseUrl}/uploads/r.png');
      expect(
        CallKitParamsBuilder.incoming(
          ringPush(extra: {'ProfilePic': ''}),
          callId: '42',
          ring: const Duration(seconds: 30),
        ).avatar,
        isNull,
      );
    });
  });
}
