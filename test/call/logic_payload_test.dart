import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/call_payload.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/core/config/env.dart';

void main() {
  group('CallPayload.parse', () {
    test('backend ring (P1): names, video from type, docIds, avatar', () {
      final p = CallPayload.parse({
        'type': 'videoCall',
        'hasVideo': '0', // the backend always sends 0 (mem #13)
        'timestamp': '1760000000000',
        'callerName': 'Ravi+Kumar',
        'channelName': 'call_5_9_1',
        'token': '007abc def',
        'callerId': '5',
        'receiverId': '9',
        'callId': '42',
        'receiverDocID': 'Null',
        'calleridDocID': 'caller-doc',
        'ProfilePic': '/uploads/ravi.png',
        'category': '3',
        'categoryName': 'Breakup',
        'is_company_account': 'false',
      })!;
      final s = p.session;
      expect(p.callId, '42');
      expect(s.role, CallRole.receiver);
      expect(s.isVideo, isTrue);
      expect(s.remote.name, 'Ravi Kumar');
      expect(s.remote.id, '5');
      expect(s.remote.documentId, 'caller-doc');
      expect(s.remote.avatarUrl, '${Env.apiBaseUrl}/uploads/ravi.png');
      expect(s.token, '007abc+def', reason: 'space → + (E-52)');
      expect(s.receiverDocId, isNull, reason: '"Null" is no id');
      expect(s.callerDocId, 'caller-doc');
      expect(s.category, '3');
      expect(s.categoryName, 'Breakup');
      expect(s.callerIsCompany, isFalse);
      expect(s.localUid, 9);
      expect(s.sentAt, DateTime.fromMillisecondsSinceEpoch(1760000000000));
      expect(p.hasJoinCreds, isTrue);
    });

    test('every alias', () {
      final p = CallPayload.parse({
        'call_id': 7,
        'caller_id': 3,
        'caller_name': 'Asha',
        'receiver_id': '11',
        'channel_name': 'room',
        'receiverToken': 'tok',
        'ts': 1760000000,
        'profilePic': 'https://cdn/x.png',
        'category_name': 'Dating',
        'is_company': true,
      })!;
      final s = p.session;
      expect(p.callId, '7');
      expect(s.callerId, '3');
      expect(s.remote.name, 'Asha');
      expect(s.receiverId, '11');
      expect(s.channelName, 'room');
      expect(s.token, 'tok');
      expect(s.remote.avatarUrl, 'https://cdn/x.png');
      expect(s.categoryName, 'Dating');
      expect(s.callerIsCompany, isTrue);
      expect(s.remote.isCompany, isTrue);
      // Seconds are read as seconds.
      expect(s.sentAt, DateTime.fromMillisecondsSinceEpoch(1760000000000));

      expect(
        CallPayload.parse({
          'CallId': '1',
          'roomId': 'r',
          'name': 'N',
        })!.session.channelName,
        'r',
      );
      expect(
        CallPayload.parse({'callId': '1', 'handle': 'H'})!.session.remote.name,
        'H',
      );
      expect(
        CallPayload.parse({
          'callId': '1',
          'isCompanyAccount': 'true',
        })!.session.callerIsCompany,
        isTrue,
      );
    });

    test('nested data wins, top-level keys stay', () {
      final p = CallPayload.parse({
        'aps': {'content-available': 1},
        'uuid': 'call_5_9_1',
        'callId': 'top',
        'data': {'callId': '42', 'channelName': 'c', 'token': 't'},
      })!;
      expect(p.callId, '42');
      expect(p.data['uuid'], 'call_5_9_1');
      expect(p.hasJoinCreds, isTrue);
    });

    test('booleans: true / "true" / 1 / "1"', () {
      for (final v in [true, 'true', 'TRUE', 1, '1']) {
        final p = CallPayload.parse({
          'callId': '1',
          '__autoAccept': v,
          '__unlock': v,
          '__isOngoingCall': v,
          '__autoOpen': v,
        })!;
        expect(p.session.autoAccept, isTrue, reason: '$v');
        expect(p.session.openedLocked, isTrue, reason: '$v');
        expect(p.ongoing, isTrue, reason: '$v');
        expect(p.autoOpen, isTrue, reason: '$v');
      }
      for (final v in [false, 'false', 0, '0', null, 'yes']) {
        final p = CallPayload.parse({'callId': '1', '__autoAccept': v})!;
        expect(p.session.autoAccept, isFalse, reason: '$v');
      }
    });

    test('video: isVideo / hasVideo / type containing "video"', () {
      bool video(Map<String, dynamic> extra) =>
          CallPayload.parse({'callId': '1', ...extra})!.session.isVideo;
      expect(video({'type': 'voiceCall'}), isFalse);
      expect(video({'type': 'videoCall', 'hasVideo': '0'}), isTrue);
      expect(video({'type': 'VIDEO_CALL'}), isTrue);
      expect(video({'isVideo': 'true'}), isTrue);
      expect(video({'hasVideo': 1}), isTrue);
      expect(video({}), isFalse);
    });

    test('timestamp: seconds or ms; staleness', () {
      final now = DateTime(2026, 10, 21, 12);
      final ms = now.millisecondsSinceEpoch;
      expect(CallPayload.sentAt('${ms ~/ 1000}'), isNotNull);
      expect(
        CallPayload.sentAt(ms ~/ 1000)!.millisecondsSinceEpoch,
        (ms ~/ 1000) * 1000,
      );
      expect(CallPayload.sentAt(ms)!.millisecondsSinceEpoch, ms);
      expect(CallPayload.sentAt('abc'), isNull);
      expect(CallPayload.sentAt(0), isNull);
      expect(CallPayload.sentAt(null), isNull);

      final old = CallPayload.parse({
        'callId': '1',
        'timestamp': '${ms - 46000}',
      })!;
      expect(old.isStale(const Duration(seconds: 45), now: now), isTrue);
      expect(old.isStale(const Duration(seconds: 120), now: now), isFalse);
      final none = CallPayload.parse({'callId': '1'})!;
      expect(none.isStale(Duration.zero, now: now), isFalse);
    });

    test('receiver defaults to me; no call id → null', () {
      expect(CallPayload.parse({'type': 'voiceCall'}), isNull);
      expect(
        CallPayload.parse({'callId': '1'}, selfId: '9')!.session.receiverId,
        '9',
      );
      expect(
        CallPayload.parse({
          'callId': '1',
          'receiverId': '4',
        }, selfId: '9')!.session.receiverId,
        '4',
      );
    });

    test('names and urls', () {
      expect(CallPayload.displayName('  '), isNull);
      expect(CallPayload.displayName('A+B'), 'A B');
      expect(
        CallPayload.absoluteUrl('uploads/a.png'),
        endsWith('/uploads/a.png'),
      );
      expect(
        CallPayload.absoluteUrl('uploads/a.png'),
        startsWith(Env.apiBaseUrl),
      );
      expect(CallPayload.absoluteUrl('HTTPS://x/y'), 'HTTPS://x/y');
      expect(CallPayload.absoluteUrl(''), isNull);
      expect(CallPayload.repairToken('006a b\n'), '006a+b');
    });

    test('FCM fingerprint (E-2)', () {
      final p = CallPayload.parse({
        'callId': '42',
        'type': 'voiceCall',
        'messageId': 'm1',
        'timestamp': '5',
      })!;
      expect(p.fingerprint, '42|voiceCall||m1||5');
    });
  });
}
