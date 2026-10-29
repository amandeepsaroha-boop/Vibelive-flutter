import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/helper/call_analytics.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/core/analytics/analytics.dart';
import 'package:vibelive/core/analytics/analytics_identity.dart';
import 'package:vibelive/core/analytics/screen_tracker.dart';

void main() {
  group('Analytics.sanitize', () {
    test('drops empty values, keeps numbers, turns bools into text', () {
      expect(
        Analytics.sanitize({
          'a': null,
          'b': '',
          'c': 'null',
          'd': double.nan,
          'e': 3,
          'f': true,
          'g': ' x ',
        }),
        {'e': 3, 'f': 'true', 'g': 'x'},
      );
    });

    test('keeps at most 25 parameters', () {
      final many = {for (var i = 0; i < 40; i++) 'p$i': i};
      expect(Analytics.sanitize(many).length, 25);
    });
  });

  group('ScreenTracker.nameFor', () {
    String name(String location) => ScreenTracker.nameFor(Uri.parse(location));

    test('known routes', () {
      expect(name('/'), 'splash');
      expect(name('/auth/login'), 'login');
      expect(name('/wallet?amount=99'), 'wallet');
      expect(name('/me/professional-details?step=rates'), 'host_profile_edit');
      expect(name('/host/onboarding'), 'host_onboarding');
    });

    test('home tabs come from ?tab=', () {
      expect(name('/home'), 'home_discover');
      expect(name('/home?tab=history'), 'home_history');
      expect(name('/home?tab=logs'), 'home_history');
      expect(name('/home?tab=me'), 'home_me');
    });

    test('unknown routes still get a Firebase-safe name', () {
      expect(name('/some/new-page'), 'route_some_new_page');
    });
  });

  group('AnalyticsIdentity.userData', () {
    test('normalizes the fields Meta matches on', () {
      final d = AnalyticsIdentity.userData({
        'mobile': '98765 43210',
        'name': 'Asha Rani',
        'gender': 'Female',
        'date_of_birth': '1999-04-07',
        'email': 'A@B.com',
      });
      expect(d.phone, '919876543210');
      expect(d.firstName, 'Asha');
      expect(d.gender, 'f');
      expect(d.dateOfBirth, '19990407');
      expect(d.email, 'A@B.com'); // lowered when sent
    });
  });

  group('CallAnalytics', () {
    final calls = CallController.instance;
    final events = <String, Map<String, Object>>{};
    final order = <String>[];

    setUp(() {
      calls.reset();
      CallAnalytics.debugReset();
      CallAnalytics.attach();
      events.clear();
      order.clear();
      Analytics.debugSink = (e, p) {
        if (e.contains(':')) return; // meta: / firebase: twins
        events[e] = p;
        order.add(e);
      };
    });

    tearDown(() {
      Analytics.debugSink = null;
      CallAnalytics.debugReset();
      calls.reset();
    });

    CallSession outgoing(String id) => CallSession(
      callId: id,
      isVideo: true,
      receiverDocId: 'host$id',
      remote: CallPeer(id: '7', documentId: 'user7'),
    );

    CallSession ring(String id) =>
        CallSession(role: CallRole.receiver, callId: id, callerId: '5');

    test('a connected call: initiated → ringing → started → ended', () {
      calls.startOutgoing(outgoing('1'));
      calls.setRinging();
      calls.setConnected();
      CallAnalytics.reason('1', CallEndReason.balanceExhausted);
      calls.end();
      expect(order, [
        'call_initiated',
        'call_ringing',
        'call_accepted',
        'call_started',
        'call_ended',
      ]);
      final ended = events['call_ended']!;
      expect(ended['call_type'], 'video');
      expect(ended['role'], 'caller');
      expect(ended['host_id'], 'host1');
      expect(ended['end_reason'], CallEndReason.balanceExhausted);
      expect(ended['duration_seconds'], 1);
    });

    test('caller gives up before an answer: call_cancelled', () {
      calls.startOutgoing(outgoing('2'));
      CallAnalytics.reason('2', CallEndReason.userHangup);
      calls.end();
      expect(order.last, 'call_cancelled');
    });

    test('nobody answered in time: call_not_answered', () {
      calls.startOutgoing(outgoing('3'));
      CallAnalytics.reason('3', CallEndReason.noAnswer);
      calls.end();
      expect(order.last, 'call_not_answered');
    });

    test('host declined (ended push before connect): call_rejected', () {
      calls.startOutgoing(outgoing('4'));
      CallAnalytics.reason('4', CallEndReason.remoteEnded);
      calls.end();
      expect(order.last, 'call_rejected');
    });

    test('receiver: a ring that goes away unanswered is call_missed', () {
      calls.receive(ring('5'));
      CallAnalytics.reason('5', CallEndReason.callerCancelled);
      calls.reset();
      expect(order, ['call_incoming', 'call_missed']);
      expect(events['call_missed']!['end_reason'], 'caller_cancelled');
    });

    test('receiver: declining is call_declined', () {
      calls.receive(ring('6'));
      CallAnalytics.reason('6', CallEndReason.declined);
      calls.reset();
      expect(order.last, 'call_declined');
    });

    test('receiver accepted but the caller never joined: call_failed', () {
      calls.receive(ring('7'));
      calls.setAccepted();
      CallAnalytics.reason('7', CallEndReason.peerNeverJoined);
      calls.end();
      expect(order, ['call_incoming', 'call_accepted', 'call_failed']);
    });

    test('the first reason wins', () {
      calls.startOutgoing(outgoing('8'));
      calls.setConnected();
      CallAnalytics.reason('8', CallEndReason.remoteHangup);
      CallAnalytics.reason('8', CallEndReason.userHangup);
      calls.end();
      expect(events['call_ended']!['end_reason'], CallEndReason.remoteHangup);
    });
  });
}
