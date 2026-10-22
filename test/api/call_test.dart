import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/callscreen/call_api.dart';
import 'package:vibelive/app/api/callscreen/call_errors.dart';
import 'package:vibelive/app/api/callscreen/call_models.dart';
import 'package:vibelive/app/api/callscreen/call_ttl.dart';
import 'package:vibelive/app/api/callscreen/pending_decline_queue.dart';
import 'package:vibelive/app/api/callscreen/review_api.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

const me = 'me-doc';
final now = DateTime.utc(2026, 10, 19, 12);

Map<String, dynamic> callRow({
  Object id = 42,
  String status = 'completed',
  bool outgoing = true,
  String type = 'voiceCall',
  Object? durationSec = 0,
  Object? duration = 0,
  String counterpartRole = 'Expert',
  DateTime? at,
  Object? review,
}) {
  final mine = {'id': 1, 'documentId': me, 'name': 'Me', 'role': 'Client'};
  final other = {
    'id': 2,
    'documentId': 'other-doc',
    'name': 'Other',
    'role': counterpartRole,
    'profilePic': {'url': 'https://cdn.test/other.png'},
  };
  return {
    'id': id,
    'documentId': 'call-$id',
    'callStatus': status,
    'type': type,
    'startTime': (at ?? now).toIso8601String(),
    'duration_sec': durationSec,
    'duration': duration,
    'totalCost': '30.5',
    'caller': outgoing ? mine : other,
    'receiver': outgoing ? other : mine,
    'review': ?review,
  };
}

CallHistoryItem item(Map<String, dynamic> row, {String? viewerRole}) =>
    CallHistoryItem(CallLog(row), viewerDocumentId: me, viewerRole: viewerRole);

void main() {
  group('CallStatus', () {
    test('parses leniently with an unknown fallback', () {
      expect(CallStatus.parse('Completed'), CallStatus.completed);
      expect(CallStatus.parse(' declined '), CallStatus.declined);
      expect(CallStatus.parse('canceled'), CallStatus.cancelled);
      expect(CallStatus.parse('reconnecting'), CallStatus.unknown);
      expect(CallStatus.parse(null), CallStatus.unknown);
      expect(CallStatus.parse(''), CallStatus.unknown);
    });

    test('closed statuses match the RN routing guard (+ admin force end)', () {
      final closed = CallStatus.values.where((s) => s.isClosed).toSet();
      expect(closed, {
        CallStatus.ended,
        CallStatus.declined,
        CallStatus.missed,
        CallStatus.cancelled,
        CallStatus.completed,
        CallStatus.forceCompleteByAdmin,
      });
    });

    test('admin force end: DB value and push value', () {
      expect(
        CallStatus.parse('force complete by admin'),
        CallStatus.forceCompleteByAdmin,
      );
      expect(
        CallStatus.parse('force_complete_by_admin'),
        CallStatus.forceCompleteByAdmin,
      );
      expect(
        CallStatus.forceCompleteByAdmin.wireValue,
        'force complete by admin',
      );
      expect(CallStatus.forceCompleteByAdmin.isClosed, isTrue);
    });

    test('CallType parses anything with "video" as video', () {
      expect(CallType.parse('videoCall'), CallType.video);
      expect(CallType.parse('VIDEO'), CallType.video);
      expect(CallType.parse('voiceCall'), CallType.voice);
      expect(CallType.parse(null), CallType.voice);
      expect(CallType.video.wireValue, 'videoCall');
    });
  });

  group('CallLog', () {
    test('maps a Strapi v5 row', () {
      final log = CallLog(
        callRow(
          type: 'videoCall',
          durationSec: 125,
          duration: '2',
          review: {'id': 9, 'rating': 4, 'comments': 'Great'},
        ),
      );
      expect(log.id, 42);
      expect(log.key, '42');
      expect(log.status, CallStatus.completed);
      expect(log.isVideo, isTrue);
      expect(log.durationSeconds, 125);
      expect(log.durationMinutes, 2);
      expect(log.hasPositiveDuration, isTrue);
      expect(log.totalCost, 30.5);
      expect(log.at, now.toLocal());
      expect(log.caller?.documentId, me);
      expect(log.receiver?.avatarUrl, 'https://cdn.test/other.png');
      expect(log.review?.rating, 4);
      expect(log.review?.comments, 'Great');
    });

    test('maps a Strapi v4 page (attributes / data wrappers)', () {
      final body = {
        'data': [
          {
            'id': 7,
            'attributes': {
              'callStatus': 'missed',
              'createdAt': '2026-10-19T09:00:00.000Z',
              'caller': {
                'data': {
                  'id': 5,
                  'attributes': {
                    'documentId': 'caller-doc',
                    'name': 'Caller',
                    'profilePic': {
                      'data': {
                        'id': 1,
                        'attributes': {'url': '/uploads/a.png'},
                      },
                    },
                  },
                },
              },
              'receiver': {
                'data': {
                  'id': 1,
                  'attributes': {'documentId': me},
                },
              },
              'review': {'data': null},
            },
          },
        ],
        'meta': {
          'pagination': {'page': 1, 'pageSize': 10, 'pageCount': 3},
        },
      };
      final page = CallHistoryPage.fromResponse(body, page: 1, pageSize: 10);
      expect(page.calls, hasLength(1));
      final log = page.calls.single;
      expect(log.id, 7);
      expect(log.status, CallStatus.missed);
      expect(log.at, DateTime.utc(2026, 10, 19, 9).toLocal());
      expect(log.caller?.name, 'Caller');
      expect(log.caller?.avatarUrl, endsWith('/uploads/a.png'));
      expect(log.caller?.avatarUrl, startsWith('http'));
      expect(log.receiver?.documentId, me);
      expect(log.review, isNull);
      expect(page.hasMore, isTrue);
    });

    test('status and type fall back to call_status / metadata', () {
      const log = CallLog({
        'call_status': 'declined',
        'metadata': {'callType': 'videoCall'},
      });
      expect(log.status, CallStatus.declined);
      expect(log.type, CallType.video);
      expect(const CallLog({}).status, CallStatus.unknown);
      expect(const CallLog({}).key, '');
    });
  });

  group('CallHistoryItem', () {
    test('direction follows the RN rules', () {
      CallDirection dir(
        String status, {
        bool outgoing = true,
        Object? sec = 0,
        Object? min = 0,
      }) => item(
        callRow(
          status: status,
          outgoing: outgoing,
          durationSec: sec,
          duration: min,
        ),
      ).direction;

      expect(dir('completed'), CallDirection.outgoing);
      expect(dir('completed', outgoing: false), CallDirection.incoming);
      expect(dir('declined'), CallDirection.declined);
      expect(dir('declined', outgoing: false), CallDirection.declined);
      expect(dir('declined', sec: 12), CallDirection.missed);
      expect(dir('declined', min: 1), CallDirection.missed);
      expect(dir('missed'), CallDirection.outgoingMissed);
      expect(dir('missed', outgoing: false), CallDirection.missed);
      expect(dir('ongoing', outgoing: false), CallDirection.incoming);
      expect(dir('pending'), CallDirection.outgoing);
    });

    test('viewer is matched by documentId or numeric id', () {
      final row = callRow();
      expect(item(row).isOutgoing, isTrue);
      expect(item(row).counterpart?.documentId, 'other-doc');
      final byId = CallHistoryItem(CallLog(row), viewerDocumentId: '1');
      expect(byId.isOutgoing, isTrue);
      final stranger = CallHistoryItem(CallLog(row), viewerDocumentId: 'x');
      expect(stranger.isOutgoing, isFalse);
      expect(stranger.counterpart?.documentId, me);
    });

    test('outcome says how the call went', () {
      expect(item(callRow(status: 'missed')).outcome, CallOutcome.missed);
      expect(item(callRow(status: 'declined')).outcome, CallOutcome.declined);
      expect(item(callRow(type: 'videoCall')).outcome, CallOutcome.videoCall);
      expect(item(callRow()).outcome, CallOutcome.voiceCall);
    });

    test('isExpert: expert role, expert relation, or a client viewer', () {
      expect(item(callRow()).isExpert, isTrue);
      final clientPeer = callRow(counterpartRole: 'Client');
      expect(item(clientPeer, viewerRole: 'Expert').isExpert, isFalse);
      expect(item(clientPeer, viewerRole: 'Client').isExpert, isTrue);
      (clientPeer['receiver'] as Map)['expert'] = {'id': 3};
      expect(item(clientPeer, viewerRole: 'Expert').isExpert, isTrue);
      (clientPeer['receiver'] as Map)['expert'] = {'data': null};
      expect(item(clientPeer, viewerRole: 'Expert').isExpert, isFalse);
    });

    test('review lookup and rating need a connected call with an expert', () {
      final talked = item(callRow(durationSec: 60));
      expect(talked.mayHaveReview, isTrue);
      expect(talked.canRate, isTrue);

      final incoming = item(callRow(durationSec: 60, outgoing: false));
      expect(incoming.mayHaveReview, isTrue);
      expect(incoming.canRate, isFalse);

      expect(item(callRow()).mayHaveReview, isFalse);
      expect(
        item(callRow(status: 'missed', durationSec: 60)).mayHaveReview,
        isFalse,
      );
      expect(
        item(callRow(durationSec: 60, counterpartRole: 'Client')).canRate,
        isFalse,
      );
    });

    test('ping only for an incoming missed/declined call in the window', () {
      const window = Duration(hours: 24);
      bool ping(Map<String, dynamic> row) =>
          item(row).canPing(window: window, now: now);

      final recent = now.subtract(const Duration(hours: 2));
      final old = now.subtract(const Duration(hours: 25));
      expect(
        ping(callRow(status: 'missed', outgoing: false, at: recent)),
        true,
      );
      expect(
        ping(callRow(status: 'declined', outgoing: false, at: recent)),
        true,
      );
      expect(ping(callRow(status: 'missed', outgoing: false, at: old)), false);
      expect(ping(callRow(status: 'missed', at: recent)), false);
      expect(ping(callRow(status: 'declined', at: recent)), false);
      expect(
        ping(callRow(status: 'completed', outgoing: false, at: recent)),
        false,
      );
      final noPeer = callRow(status: 'missed', outgoing: false, at: recent)
        ..remove('caller');
      expect(ping(noPeer), false);
    });

    test('ping window comes from expert_ping_config', () {
      expect(CallHistoryItem.pingWindow(null), const Duration(hours: 24));
      expect(
        CallHistoryItem.pingWindow({'validity_hours': 6}),
        const Duration(hours: 6),
      );
      expect(
        CallHistoryItem.pingWindow({'validity_hours': '1.5'}),
        const Duration(minutes: 90),
      );
      expect(
        CallHistoryItem.pingWindow({'validity_hours': 0}),
        const Duration(hours: 24),
      );
    });
  });

  group('CallHistoryPage', () {
    CallHistoryPage page(
      List<Map<String, dynamic>> rows, {
      int number = 1,
      int? pageCount,
    }) => CallHistoryPage(
      calls: [for (final r in rows) CallLog(r)],
      page: number,
      pageSize: 3,
      pageCount: pageCount,
    );

    test('hasMore trusts pageCount, else a full page', () {
      final rows = [callRow(id: 1), callRow(id: 2), callRow(id: 3)];
      expect(page(rows, pageCount: 2).hasMore, isTrue);
      expect(page(rows, number: 2, pageCount: 2).hasMore, isFalse);
      expect(page(rows).hasMore, isTrue);
      expect(page(rows.take(2).toList()).hasMore, isFalse);
    });

    test('round-trips through JSON (disk copy)', () {
      final original = CallHistoryPage(
        calls: [CallLog(callRow(id: 1)), CallLog(callRow(id: 2))],
        page: 1,
        pageSize: 10,
        pageCount: 4,
        total: 37,
      );
      final restored = CallHistoryPage.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored.calls.map((c) => c.id), [1, 2]);
      expect(restored.calls.first.receiver?.name, 'Other');
      expect(restored.page, 1);
      expect(restored.pageSize, 10);
      expect(restored.pageCount, 4);
      expect(restored.total, 37);
      expect(restored.hasMore, isTrue);
    });

    test('merge dedupes across pages and sorts newest first', () {
      DateTime t(int h) => now.subtract(Duration(hours: h));
      final first = page([
        callRow(id: 3, at: t(1), status: 'missed'),
        callRow(id: 2, at: t(2)),
      ]);
      final second = page([
        callRow(id: 2, at: t(2), status: 'declined'),
        callRow(id: 1, at: t(3)),
        callRow(id: 5, at: t(1)),
      ]);
      final merged = CallHistoryPage.merge([first, second]);
      expect(merged.map((c) => c.id), [3, 5, 2, 1]);
      expect(merged[2].status, CallStatus.completed, reason: 'page 1 wins');
    });
  });

  group('Review', () {
    test('normalizeRating accepts the known shapes within 0–5', () {
      expect(Review.normalizeRating(4), 4);
      expect(Review.normalizeRating('3.5'), 3.5);
      expect(Review.normalizeRating({'value': 2}), 2);
      expect(
        Review.normalizeRating({
          'data': {
            'attributes': {'value': 5},
          },
        }),
        5,
      );
      expect(Review.normalizeRating(7), 0);
      expect(Review.normalizeRating(null, 3), 3);
      expect(Review.normalizeRating('x', 9), 5);
    });

    test('hasContent needs stars or a comment', () {
      expect(const Review({'rating': 0, 'comments': ''}).hasContent, isFalse);
      expect(const Review({'rating': 0, 'comments': 'ok'}).hasContent, isTrue);
      expect(const Review({'rating': 3}).hasContent, isTrue);
    });

    test('ReviewPage reads pagination', () {
      final body = {
        'data': [
          {
            'id': 1,
            'rating': 5,
            'user': {'name': 'A'},
          },
        ],
        'meta': {
          'pagination': {'page': 1, 'pageCount': 2, 'total': 11},
        },
      };
      final p = ReviewPage.fromResponse(body, page: 1);
      expect(p.reviews.single.author?.name, 'A');
      expect(p.total, 11);
      expect(p.hasMore, isTrue);
      expect(ReviewPage.fromResponse({'data': []}, page: 1).hasMore, isFalse);
    });
  });

  group('InitiatedCall', () {
    test('busy and complete answers', () {
      expect(InitiatedCall.isBusyResponse({'status': 'BUSY'}), isTrue);
      expect(InitiatedCall.isBusyResponse({'status': 'ok'}), isFalse);
      final call = InitiatedCall.tryParse({
        'callDetails': {'id': 99, 'documentId': 'c99'},
        'channelName': 'room',
        'callerToken': 'tok',
        'receiverDocId': 'r1',
      });
      expect(call?.callId, '99');
      expect(call?.callDocumentId, 'c99');
      expect(call?.channelName, 'room');
      expect(call?.callerToken, 'tok');
      expect(call?.receiverDocId, 'r1');
      expect(
        InitiatedCall.tryParse({
          'callDetails': {'id': 99},
          'channelName': 'room',
        }),
        isNull,
      );
    });
  });

  group('request bodies', () {
    final at = DateTime.utc(2026, 10, 19, 10, 0, 0, 123, 456);

    test('decline matches RN declineCall', () {
      final input = CallEndInput.decline(
        callId: '42',
        type: CallType.video,
        callerDocumentId: 'caller-doc',
        endedById: 7,
        at: at,
      );
      expect(input.toJson(), {
        'callId': '42',
        'status': 'declined',
        'startTime': '2026-10-19T10:00:00.123Z',
        'endTime': '2026-10-19T10:00:00.123Z',
        'duration': 0,
        'totalCost': 0,
        'type': 'videoCall',
        'calleridDocID': 'caller-doc',
        'endedById': 7,
      });
    });

    test('end call defaults times to now and round-trips', () {
      const input = CallEndInput(
        callId: '1',
        endedById: 3,
        durationSeconds: 65,
      );
      final json = input.toJson(now: at);
      expect(json['status'], 'completed');
      expect(json['startTime'], '2026-10-19T10:00:00.123Z');
      expect(json['endedById'], 3);
      // RN omitted undefined keys.
      expect(json.containsKey('calleridDocID'), isFalse);
      expect(CallEndInput.fromJson(json).toJson(), json);
    });

    test('caller cancel sends no status (E-92)', () {
      final json = CallEndInput.cancel(
        callId: '8',
        endedById: 11,
        type: CallType.video,
      ).toJson(now: at);
      expect(json.containsKey('status'), isFalse);
      expect(json['endedById'], 11);
      expect(json['type'], 'videoCall');
      final back = CallEndInput.fromJson(json);
      expect(back.status, isNull);
      expect(back.toJson(now: at), json);
    });

    test('initiate call defaults', () {
      const input = InitiateCallInput(callerId: 1, receiverId: 2);
      final json = input.toJson(now: at);
      expect(json['role'], 'Client');
      expect(json['type'], 'voiceCall');
      expect(json['userPlatform'], isNotEmpty);
      expect(json.containsKey('categoryId'), isFalse);
      expect(json['startTime'], '2026-10-19T10:00:00.123Z');
      expect(input.hasParticipants, isTrue);
      expect(
        const InitiateCallInput(callerId: '', receiverId: 2).hasParticipants,
        isFalse,
      );
      expect(
        const InitiateCallInput(callerId: 1, receiverId: null).hasParticipants,
        isFalse,
      );
    });

    test('status update omits missing ids and the start time', () {
      // No startTime by default: the server clock is the billing start (E-87).
      final json = const CallStatusUpdate(
        callId: '5',
        receiverId: '9',
      ).toJson();
      expect(json, {'callId': '5', 'receiverId': '9', 'status': 'ongoing'});
    });

    test('status update carries the answering device (E-76)', () {
      final json = CallStatusUpdate(
        callId: '5',
        callerId: '1',
        receiverId: '9',
        type: CallType.video,
        answeredDeviceId: 'ios-abc',
        startTime: at,
      ).toJson();
      expect(json, {
        'callId': '5',
        'callerId': '1',
        'receiverId': '9',
        'status': 'ongoing',
        'startTime': '2026-10-19T10:00:00.123Z',
        'type': 'videoCall',
        'answeredDeviceId': 'ios-abc',
      });
    });

    test('UpdateCall answer: alreadyOngoing', () {
      expect(
        UpdateCallResult.fromResponse({
          'ok': true,
          'alreadyOngoing': true,
        }).alreadyOngoing,
        isTrue,
      );
      expect(
        UpdateCallResult.fromResponse({
          'id': 5,
          'callStatus': 'ongoing',
        }).alreadyOngoing,
        isFalse,
      );
      expect(UpdateCallResult.fromResponse(null).alreadyOngoing, isFalse);
    });

    test('review input', () {
      const empty = ReviewInput(expertId: 'e', userId: 'u', rating: 0);
      expect(empty.hasContent, isFalse);
      expect(
        const ReviewInput(
          expertId: 'e',
          userId: 'u',
          rating: 0,
          comments: ' nice ',
        ).hasContent,
        isTrue,
      );
      expect(
        const ReviewInput(expertId: 'e', userId: 'u', rating: 4).toJson(),
        {'expert': 'e', 'user': 'u', 'rating': 4, 'comments': ''},
      );
    });
  });

  group('CallApiExceptionX', () {
    ApiException err(int status, String message, {bool nested = false}) =>
        ApiException(
          ApiErrorType.rejected,
          statusCode: status,
          data: nested
              ? {
                  'error': {'message': message},
                }
              : {'message': message},
        );

    test('benign ringing ack', () {
      expect(
        err(
          409,
          'Call is not in pending state',
          nested: true,
        ).isBenignRingingAck,
        isTrue,
      );
      expect(err(409, 'Conflict').isBenignRingingAck, isFalse);
      expect(err(400, 'not in pending state').isBenignRingingAck, isFalse);
    });

    test('benign decline', () {
      expect(err(404, '').isBenignDecline, isTrue);
      expect(err(400, 'Call has been ended already').isBenignDecline, isTrue);
      expect(err(400, 'Call not found', nested: true).isBenignDecline, isTrue);
      expect(err(400, 'Bad payload').isBenignDecline, isFalse);
      expect(err(500, 'already').isBenignDecline, isFalse);
    });

    test('call already ended', () {
      expect(err(409, 'Already ended').isCallAlreadyEnded, isTrue);
      expect(
        err(500, 'Call has been ended already').isCallAlreadyEnded,
        isTrue,
      );
      expect(err(500, 'boom').isCallAlreadyEnded, isFalse);
    });

    test('fallback key spares connectivity errors and existing keys', () {
      const rejected = ApiException(ApiErrorType.rejected);
      expect(
        rejected.withFallbackKey(CallErrorKeys.pingFailed).messageKey,
        CallErrorKeys.pingFailed,
      );
      const offline = ApiException(ApiErrorType.network);
      expect(
        offline.withFallbackKey(CallErrorKeys.pingFailed).messageKey,
        null,
      );
      const busy = ApiException(
        ApiErrorType.conflict,
        messageKey: CallErrorKeys.userBusy,
      );
      expect(
        busy.withFallbackKey(CallErrorKeys.initiateFailed).isUserBusy,
        true,
      );
    });

    test('withCallFallback relabels thrown errors', () async {
      await expectLater(
        withCallFallback<void>(
          CallErrorKeys.reviewFailed,
          () async => throw const ApiException(ApiErrorType.server),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.messageKey,
            'messageKey',
            CallErrorKeys.reviewFailed,
          ),
        ),
      );
    });
  });

  group('CallTtl', () {
    test('invite staleness', () {
      final ms = now.millisecondsSinceEpoch;
      expect(CallTtl.isStale(ms - 46000, now: now), isTrue);
      expect(CallTtl.isStale('${ms - 44000}', now: now), isFalse);
      expect(CallTtl.isStale(null, now: now), isFalse);
      expect(CallTtl.isStale('abc', now: now), isFalse);
      expect(CallTtl.isStale(0, now: now), isFalse);
      expect(
        CallTtl.isStale(ms - 90000, ttl: CallTtl.incomingPayload, now: now),
        isFalse,
      );
    });
  });

  group('i18n', () {
    test('call error keys exist in en and hi with the same key set', () {
      Set<String> flat(Map<String, dynamic> m, [String prefix = '']) => {
        for (final e in m.entries)
          ...(e.value is Map
              ? flat(
                  Map<String, dynamic>.from(e.value as Map),
                  '$prefix${e.key}.',
                )
              : {'$prefix${e.key}'}),
      };
      Set<String> load(String lang) => flat(
        jsonDecode(File('assets/i18n/$lang/call.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final en = load('en');
      expect(load('hi'), en);
      for (final key in const [
        CallErrorKeys.userBusy,
        CallErrorKeys.invalidResponse,
        CallErrorKeys.initiateFailed,
        CallErrorKeys.missingParticipants,
        CallErrorKeys.reviewEmpty,
        CallErrorKeys.expertUnresolved,
        CallErrorKeys.reviewFailed,
        CallErrorKeys.pingFailed,
      ]) {
        expect(key, startsWith('call:'));
        expect(en, contains(key.substring('call:'.length)));
      }
    });
  });

  group('PendingDeclineQueue', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await AppPrefs.init();
    });

    setUp(() => AppPrefs.remove(PendingDeclineQueue.storageKey));

    CallEndInput decline(String id) =>
        CallEndInput.decline(callId: id, endedById: 'u1', at: now);

    test('enqueue replaces an earlier entry for the same call', () async {
      await PendingDeclineQueue.enqueue(decline('a'), now: now);
      await PendingDeclineQueue.enqueue(decline('b'), now: now);
      final later = now.add(const Duration(minutes: 1));
      await PendingDeclineQueue.enqueue(decline('a'), now: later);
      final pending = PendingDeclineQueue.pending;
      expect(pending.map((d) => d.callId), ['b', 'a']);
      expect(pending.last.enqueuedAt.isAtSameMomentAs(later), isTrue);
    });

    test('keeps at most the newest 20 and stores the RN shape', () async {
      for (var i = 0; i < 25; i++) {
        await PendingDeclineQueue.enqueue(decline('c$i'), now: now);
      }
      final pending = PendingDeclineQueue.pending;
      expect(pending, hasLength(PendingDeclineQueue.maxItems));
      expect(pending.first.callId, 'c5');
      final stored =
          jsonDecode(AppPrefs.getString(PendingDeclineQueue.storageKey)!)
              as List;
      expect(
        (stored.first as Map).keys,
        containsAll(['postData', 'enqueuedAt']),
      );
    });

    test('flush sends each body unchanged and empties the queue', () async {
      await PendingDeclineQueue.enqueue(decline('a'), now: now);
      await PendingDeclineQueue.enqueue(decline('b'), now: now);
      final sent = <Map<String, dynamic>>[];
      final count = await PendingDeclineQueue.flush(
        send: (input) async => sent.add(input.toJson()),
        clock: () => now,
      );
      expect(count, 2);
      expect(sent.map((b) => b['callId']), ['a', 'b']);
      expect(sent.first, decline('a').toJson());
      expect(PendingDeclineQueue.pending, isEmpty);
      expect(AppPrefs.getString(PendingDeclineQueue.storageKey), isNull);
    });

    test('failures stay; closed-on-server and expired entries go', () async {
      final old = now.subtract(const Duration(hours: 7));
      await PendingDeclineQueue.enqueue(decline('expired'), now: old);
      await PendingDeclineQueue.enqueue(decline('offline'), now: now);
      await PendingDeclineQueue.enqueue(decline('gone'), now: now);
      final attempted = <String>[];
      final count = await PendingDeclineQueue.flush(
        send: (input) async {
          attempted.add(input.callId);
          throw input.callId == 'gone'
              ? const ApiException(ApiErrorType.notFound, statusCode: 404)
              : const ApiException(ApiErrorType.network);
        },
        clock: () => now,
      );
      expect(count, 0);
      expect(attempted, ['offline', 'gone']);
      expect(PendingDeclineQueue.pending.map((d) => d.callId), ['offline']);
    });

    test('a decline queued during a flush survives it', () async {
      await PendingDeclineQueue.enqueue(decline('a'), now: now);
      await PendingDeclineQueue.flush(
        send: (input) => PendingDeclineQueue.enqueue(decline('late'), now: now),
        clock: () => now,
      );
      expect(PendingDeclineQueue.pending.map((d) => d.callId), ['late']);
    });

    test('concurrent flushes share one run', () async {
      await PendingDeclineQueue.enqueue(decline('a'), now: now);
      final gate = Completer<void>();
      var calls = 0;
      Future<void> send(CallEndInput _) async {
        calls++;
        await gate.future;
      }

      final first = PendingDeclineQueue.flush(send: send, clock: () => now);
      final second = PendingDeclineQueue.flush(send: send, clock: () => now);
      gate.complete();
      expect(await Future.wait([first, second]), [1, 1]);
      expect(calls, 1);
    });

    test('corrupt storage reads as empty', () async {
      await AppPrefs.setString(PendingDeclineQueue.storageKey, '{oops');
      expect(PendingDeclineQueue.pending, isEmpty);
      expect(await PendingDeclineQueue.flush(send: (_) async {}), 0);
    });
  });
}
