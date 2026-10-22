import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/call/feedback_sheet.dart';
import 'package:vibelive/app/callscreen/call/helper/callback_data.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'call_support/call_harness.dart';

const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

/// permission_handler answers: 0 denied, 1 granted, 4 permanently denied.
void _mockPermissions(int status) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_permissions, (call) async {
        if (call.method == 'checkPermissionStatus') return status;
        return null;
      });
}

void main() {
  late CallBackend backend;
  setUpAll(callSetUpAll);
  setUp(() async => backend = await callSetUp());
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissions, null),
  );

  group('feedback sheet', () {
    Future<Future<FeedbackExit?>> open(WidgetTester tester) async {
      late Future<FeedbackExit?> result;
      await pumpCallApp(
        tester,
        initial: AppRoutes.home,
        homeChild: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                result = showFeedbackSheet(context, name: 'Ananya'),
            child: const Text('RATE'),
          ),
        ),
      );
      await tester.tap(find.text('RATE'));
      await pumpMs(tester, 600);
      return result;
    }

    testWidgets('stars enable Submit; Skip closes with "skipped"', (
      tester,
    ) async {
      final result = await open(tester);
      expect(find.text('RATE YOUR CALL EXPERIENCE'), findsOneWidget);
      expect(find.text('How was your session with Ananya?'), findsOneWidget);
      expect(find.text('Block this User'), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNWidgets(5));

      await tester.tap(find.byIcon(Icons.star_border).at(3));
      await pumpMs(tester, 100);
      expect(find.byIcon(Icons.star), findsNWidgets(4));

      await tester.tap(find.text('Skip & Continue'));
      await pumpMs(tester, 100);
      expect(await result, FeedbackExit.skipped);
      expect(find.text('RATE YOUR CALL EXPERIENCE'), findsNothing);
      await finishCall(tester);
    });

    testWidgets('iPhone SE keyboard: Submit stays above it, no overflow', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byType(TextField));
      // iOS: the keyboard (+ suggestions) as the bottom inset, no bottom
      // padding while it is up; the status bar stays.
      tester.view
        ..viewInsets = const FakeViewPadding(bottom: 260 * 3.0)
        ..padding = const FakeViewPadding(top: 20 * 3.0);
      await pumpMs(tester, 300);

      final submit = tester.getRect(find.text('SUBMIT FEEDBACK'));
      expect(submit.bottom, lessThanOrEqualTo(se.height - 260));
      expect(submit.top, greaterThan(20));
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Great talk ' * 40);
      await pumpMs(tester, 100);
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text
            .length,
        300,
      );
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });

    testWidgets('320 wide in Hindi: the five stars fit', (tester) async {
      late Future<FeedbackExit?> result;
      await pumpCallApp(
        tester,
        initial: AppRoutes.home,
        size: narrow,
        locale: const Locale('hi'),
        homeChild: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showFeedbackSheet(context),
            child: const Text('RATE'),
          ),
        ),
      );
      await tester.tap(find.text('RATE'));
      await pumpMs(tester, 600);
      expect(find.text('अपने कॉल अनुभव को रेटिंग दें'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Backdrop tap = skip.
      await tester.tapAt(const Offset(160, 40));
      await pumpMs(tester, 100);
      expect(await result, FeedbackExit.skipped);
      await finishCall(tester);
    });
    testWidgets('submit: loader, nothing else live until it is sent (U8)', (
      tester,
    ) async {
      // The connected call being rated (expert profile known).
      CallController.instance.debugSet(
        callOf(
          phase: CallPhase.ended,
          role: CallRole.caller,
          connectedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          endedAt: DateTime.now(),
        ).copyWith(receiverDocId: 'exp7'),
      );
      final result = await open(tester);
      var closed = false;
      unawaited(result.then((_) => closed = true));
      await tester.tap(find.byIcon(Icons.star_border).at(4));
      await pumpMs(tester, 100);

      final slow = backend.gate = Completer<void>();
      await tester.tap(find.text('SUBMIT FEEDBACK'));
      await pumpMs(tester, 100);
      expect(backend.requests, contains('POST /api/reviews'));
      expect(find.text('SUBMIT FEEDBACK'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Skip, Block and the backdrop do nothing while it is sent.
      await tester.tap(find.text('Skip & Continue'));
      await tester.tap(find.text('Block this User'));
      await tester.tapAt(const Offset(180, 40));
      await pumpMs(tester, 300);
      expect(closed, isFalse);
      expect(find.text('Block Ananya?'), findsNothing);
      expect(find.text('RATE YOUR CALL EXPERIENCE'), findsOneWidget);

      slow.complete();
      backend.gate = null;
      await pumpMs(tester, 200);
      expect(await result, FeedbackExit.submitted);
      expect(find.text('RATE YOUR CALL EXPERIENCE'), findsNothing);
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });

    testWidgets('closed from outside mid-submit: no crash (U8)', (
      tester,
    ) async {
      CallController.instance.debugSet(
        callOf(
          phase: CallPhase.ended,
          role: CallRole.caller,
          connectedAt: DateTime.now().subtract(const Duration(minutes: 1)),
          endedAt: DateTime.now(),
        ),
      );
      await open(tester);
      await tester.tap(find.byIcon(Icons.star_border).at(2));
      await pumpMs(tester, 100);
      final slow = backend.gate = Completer<void>();
      await tester.tap(find.text('SUBMIT FEEDBACK'));
      await pumpMs(tester, 100);

      // Something else tears the sheet down while the review is sent.
      await tester.pumpWidget(const SizedBox());
      slow.complete();
      backend.gate = null;
      await pumpMs(tester, 200);
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });
  });

  group('callback sheet', () {
    testWidgets('a nudge shows the host and their rates', (tester) async {
      final nudges = ValueNotifier<CallbackRequest?>(null);
      await pumpCallApp(tester, initial: AppRoutes.home, callbacks: nudges);

      nudges.value = const CallbackRequest({
        'type': 'PING_CLIENT',
        'expertId': '70',
        'expertDocId': 'exp7',
        'expertName': 'Meera',
        'categoryName': 'Breakup',
      });
      await pumpMs(tester, 600);

      expect(nudges.value, isNull); // taken
      expect(backend.requests, contains('GET /api/expert-profiles'));
      expect(find.text('Expert Callback'), findsOneWidget);
      expect(find.text('REQUEST RECEIVED'), findsOneWidget);
      expect(find.text('Meera'), findsOneWidget);
      expect(find.text('Breakup'), findsOneWidget);
      expect(find.text('Rs 20/MIN'), findsOneWidget);
      expect(find.text('Rs 30/MIN'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tapAt(const Offset(180, 40)); // backdrop
      await pumpMs(tester, 400);
      expect(find.text('Expert Callback'), findsNothing);
      await finishCall(tester);
    });

    testWidgets('held while a call page is on top, shown after (U5)', (
      tester,
    ) async {
      CallController.instance.debugSet(
        callOf(phase: CallPhase.ongoing, connectedAt: DateTime.now()),
      );
      final nudges = ValueNotifier<CallbackRequest?>(null);
      final router = await pumpCallApp(tester, callbacks: nudges);

      nudges.value = const CallbackRequest({
        'expertId': '70',
        'expertDocId': 'exp7',
        'expertName': 'Meera',
      });
      await pumpMs(tester, 600);
      expect(nudges.value, isNull); // taken, held
      expect(find.text('Expert Callback'), findsNothing);

      router.go(AppRoutes.home);
      await pumpMs(tester, 600);
      expect(find.text('Expert Callback'), findsOneWidget);
      expect(find.text('Meera'), findsOneWidget);
      await tester.tapAt(const Offset(180, 40)); // backdrop
      await pumpMs(tester, 400);
      await finishCall(tester);
    });

    test('the button tapped picks the rate (A11)', () {
      const data = CallbackData(
        expertId: '70',
        expertUserDocId: 'usr7',
        voicePrice: 20,
        videoPrice: 30,
      );
      expect(data.targetFor(video: false)!.ratePerMin, 20);
      expect(data.targetFor(video: true)!.ratePerMin, 30);
      expect(data.targetFor(video: true)!.receiverDocId, 'usr7');
      // Unknown (0): the logic looks it up.
      const free = CallbackData(expertId: '70');
      expect(free.targetFor(video: false)!.ratePerMin, isNull);
      expect(const CallbackData(expertId: null).targetFor(video: true), isNull);
    });

    testWidgets('never shown to the host who sent it', (tester) async {
      final nudges = ValueNotifier<CallbackRequest?>(null);
      await pumpCallApp(tester, initial: AppRoutes.home, callbacks: nudges);
      nudges.value = const CallbackRequest({'expertId': '1'}); // me
      await pumpMs(tester, 600);
      expect(find.text('Expert Callback'), findsNothing);
      await finishCall(tester);
    });
  });

  group('return-to-call bar', () {
    testWidgets('shows name + timer while a call runs off the call screen', (
      tester,
    ) async {
      await pumpCallApp(tester, initial: AppRoutes.home);
      expect(find.text('RETURN TO CALL'), findsNothing);

      await setCall(
        tester,
        callOf(phase: CallPhase.calling, role: CallRole.caller),
      );
      expect(find.text('RETURN TO CALL'), findsOneWidget);
      expect(find.text(' · Ananya'), findsOneWidget);
      expect(find.text('CALLING'), findsOneWidget);

      await setCall(
        tester,
        callOf(
          phase: CallPhase.ongoing,
          role: CallRole.caller,
          connectedAt: DateTime.now().subtract(const Duration(seconds: 7)),
        ),
      );
      expect(find.text('00:07'), findsOneWidget);

      // A ring for this device is the incoming screen's, not the bar's.
      await setCall(tester, callOf());
      expect(find.text('RETURN TO CALL'), findsNothing);
      await setCall(tester, CallSession.idle);
      expect(find.text('RETURN TO CALL'), findsNothing);
      await finishCall(tester);
    });

    testWidgets('hidden while the call screen is on top of Home', (
      tester,
    ) async {
      CallController.instance.debugSet(
        callOf(phase: CallPhase.ongoing, connectedAt: DateTime.now()),
      );
      final router = await pumpCallApp(tester, initial: AppRoutes.home);
      expect(find.text('RETURN TO CALL'), findsOneWidget);

      unawaited(router.push(AppRoutes.call));
      await pumpMs(tester, 200);
      // Home is still mounted under the call screen: its bar is gone too.
      expect(find.text('RETURN TO CALL', skipOffstage: false), findsNothing);
      await finishCall(tester);
    });

    testWidgets('320 wide, Hindi, long name: no overflow', (tester) async {
      await pumpCallApp(
        tester,
        initial: AppRoutes.home,
        size: narrow,
        locale: const Locale('hi'),
      );
      await setCall(
        tester,
        callOf(
          phase: CallPhase.accepted,
          name: 'Venkata Lakshmi Narasimha Subrahmanyam',
        ),
      );
      expect(find.text('कॉल पर लौटें'), findsOneWidget);
      expect(find.text('कनेक्ट हो रहा है...'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });
  });

  group('permission bar', () {
    testWidgets('blocked mic: red "Settings" bar on the call screen', (
      tester,
    ) async {
      _mockPermissions(4);
      CallController.instance.debugSet(
        callOf(phase: CallPhase.ongoing, connectedAt: DateTime.now()),
      );
      await pumpCallApp(tester);
      await pumpMs(tester, 200);
      expect(
        find.text('Microphone permission is required for calls'),
        findsOneWidget,
      );
      expect(find.text('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finishCall(tester);
    });

    testWidgets('denied (maybe never asked): waits 2.5 s, then "Allow"', (
      tester,
    ) async {
      _mockPermissions(0);
      CallController.instance.debugSet(callOf(video: true));
      await pumpCallApp(tester, initial: AppRoutes.incomingCall);
      await pumpMs(tester, 1000);
      expect(find.text('Allow'), findsNothing);
      await pumpMs(tester, 2000);
      expect(
        find.text('Microphone & camera permission is required for calls'),
        findsOneWidget,
      );
      expect(find.text('Allow'), findsOneWidget);
      await finishCall(tester);
    });

    testWidgets('granted: nothing', (tester) async {
      _mockPermissions(1);
      CallController.instance.debugSet(
        callOf(phase: CallPhase.ongoing, connectedAt: DateTime.now()),
      );
      await pumpCallApp(tester);
      await pumpMs(tester, 3000);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('Allow'), findsNothing);
      await finishCall(tester);
    });
  });
}
