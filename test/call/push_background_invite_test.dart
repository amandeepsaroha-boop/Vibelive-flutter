import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/native/native_call_marks.dart';
import 'package:vibelive/app/callscreen/helper/push/call_push_handler.dart';
import 'package:vibelive/app/callscreen/helper/push/push_envelope.dart';
import 'package:vibelive/app/callscreen/helper/state/call_dedup.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

/// A genuine FCM ring (backend P1).
Map<String, Object?> invite(String callId) => {
  'type': 'voiceCall',
  'callerName': 'Sharad Singh',
  'channelName': 'call_7_9_$callId',
  'token': '006abc',
  'callerId': '7',
  'receiverId': '9',
  'callId': callId,
};

PushEnvelope env(Map<String, Object?> data) => PushEnvelope.fromMap(data);

void main() {
  final invites = <(Map<String, dynamic>, bool, CallPushSource)>[];
  final acks = <(String, String)>[];
  final rung = <String>[];
  var android = true;

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPrefs.init();
  });

  setUp(() {
    invites.clear();
    acks.clear();
    rung.clear();
    android = true;
    CallDedup.instance.reset();
    CallPushHandler.isAndroid = () => android;
    CallPushHandler.ringer = (m, callId, now) async {
      rung.add(callId);
      return true;
    };
    CallPushHandler.sendRingingAck =
        ({required String callId, required String receiverId}) async {
          acks.add((callId, receiverId));
          return true;
        };
    CallPushHandler.onInvite =
        (data, {required bool foreground, CallPushSource? source}) async {
          invites.add((data, foreground, source ?? CallPushSource.fcm));
        };
  });

  group('A1: FCM background isolate invite', () {
    test('rings, acks once, and never reaches the call logic', () async {
      await CallPushHandler.handle(
        env(invite('9001')),
        source: CallPushSource.fcm,
        foreground: false,
        background: true,
      );
      expect(rung, ['9001']);
      expect(invites, isEmpty, reason: 'onInvite arms the 60 s ring timer');
      expect(acks, [('9001', '9')]);
      expect(CallController.instance.value.phase, CallPhase.idle);
      expect(await NativeCallMarks.wasAcked('9001'), isTrue);
    });

    test('a second delivery never acks again', () async {
      for (var i = 0; i < 2; i++) {
        await CallPushHandler.handle(
          env(invite('9002')),
          source: CallPushSource.fcm,
          foreground: false,
          background: true,
        );
      }
      expect(acks, [('9002', '9')]);
      expect(invites, isEmpty);
    });

    test('no ringer shown → no ack', () async {
      CallPushHandler.ringer = (m, callId, now) async => false;
      await CallPushHandler.handle(
        env(invite('9003')),
        source: CallPushSource.fcm,
        foreground: false,
        background: true,
      );
      expect(acks, isEmpty);
      expect(invites, isEmpty);
    });

    test('iOS background isolate: VoIP owns ringing, nothing here', () async {
      android = false;
      await CallPushHandler.handle(
        env(invite('9004')),
        source: CallPushSource.fcm,
        foreground: false,
        background: true,
      );
      expect(rung, isEmpty);
      expect(acks, isEmpty);
      expect(invites, isEmpty);
    });

    test('UI isolate, app not in front: rings and tells the logic', () async {
      await CallPushHandler.handle(
        env(invite('9005')),
        source: CallPushSource.fcm,
        foreground: false,
      );
      expect(rung, ['9005']);
      expect(invites.single.$2, isFalse);
      expect(acks, isEmpty, reason: 'the UI isolate logic acks');
    });

    test('UI isolate in front: in-app screen, no plugin ringer', () async {
      await CallPushHandler.handle(
        env(invite('9006')),
        source: CallPushSource.fcm,
        foreground: true,
      );
      expect(rung, isEmpty);
      expect(invites.single.$2, isTrue);
    });

    test('the UI isolate adopts the background ack (A8)', () async {
      await CallPushHandler.handle(
        env(invite('9007')),
        source: CallPushSource.fcm,
        foreground: false,
        background: true,
      );
      await CallPushHandler.adoptBackgroundAck('9007');
      expect(CallDedup.instance.beginAck('9007'), isFalse);
      // A call the background isolate never acked is left to the logic.
      await CallPushHandler.adoptBackgroundAck('9999');
      expect(CallDedup.instance.beginAck('9999'), isTrue);
    });
  });

  group('I9: push age', () {
    final now = DateTime.utc(2026, 10, 21, 12);

    test('milliseconds and seconds timestamps', () {
      final ms = now.subtract(const Duration(seconds: 30));
      expect(
        CallPushHandler.ageOf(
          PushEnvelope.timestampOf({
            'timestamp': '${ms.millisecondsSinceEpoch}',
          }),
          now,
        ),
        const Duration(seconds: 30),
      );
      final secs = ms.millisecondsSinceEpoch ~/ 1000;
      expect(
        CallPushHandler.ageOf(
          PushEnvelope.timestampOf({'timestamp': '$secs'}),
          now,
        ),
        const Duration(seconds: 30),
      );
    });

    test('unknown, never stale: none, future, absurd', () {
      expect(CallPushHandler.ageOf(null, now), isNull);
      expect(
        CallPushHandler.ageOf(now.add(const Duration(minutes: 3)), now),
        isNull,
      );
      expect(
        CallPushHandler.ageOf(now.subtract(const Duration(days: 400)), now),
        isNull,
      );
      expect(
        CallPushHandler.ageOf(now.subtract(const Duration(minutes: 5)), now),
        const Duration(minutes: 5),
      );
    });

    test('ring rejection: skew rings, a late ring is stale', () async {
      await AppPrefs.setString('session_user', '{"id": 9}');
      addTearDown(() => AppPrefs.remove('session_user'));
      final future = DateTime.now().add(const Duration(hours: 2));
      expect(
        await CallPushHandler.ringRejection(
          env({
            ...invite('9010'),
            'timestamp': '${future.millisecondsSinceEpoch}',
          }),
          '9010',
        ),
        isNull,
      );
      final old = DateTime.now().subtract(const Duration(minutes: 10));
      expect(
        await CallPushHandler.ringRejection(
          env({
            ...invite('9011'),
            'timestamp': '${old.millisecondsSinceEpoch}',
          }),
          '9011',
        ),
        'stale',
      );
    });
  });
}
