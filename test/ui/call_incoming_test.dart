import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/callscreen/call/call_avatar.dart';
import 'package:vibelive/app/callscreen/call/call_screen.dart';
import 'package:vibelive/app/callscreen/call/incoming/incoming_actions.dart';
import 'package:vibelive/app/callscreen/call/incoming/incoming_intro.dart';
import 'package:vibelive/app/callscreen/call/incoming/incoming_safety_card.dart';
import 'package:vibelive/app/callscreen/call/incoming_call_screen.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/component/pressable.dart';
import 'package:vibelive/core/router/app_router.dart';

import 'call_support/call_harness.dart';

Finder _pressable(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

const _hindiName = 'अनन्या कृष्णमूर्ति शर्मा';
const _iphone5 = Size(320, 568);

/// Bottom of the last visible line of the intro (the call type).
double _introBottom(WidgetTester tester) => tester
    .getRect(
      find
          .descendant(
            of: find.byType(IncomingIntro),
            matching: find.byType(RichText),
          )
          .last,
    )
    .bottom;

void main() {
  late CallBackend backend;
  setUpAll(callSetUpAll);
  setUp(() async => backend = await callSetUp());

  Future<void> openIncoming(
    WidgetTester tester,
    CallSession call, {
    Size size = se,
    EdgeInsets safeArea = seInsets,
    Locale locale = const Locale('en'),
  }) async {
    // The logic publishes the ring before it routes here.
    CallController.instance.debugSet(call);
    await pumpCallApp(
      tester,
      initial: AppRoutes.incomingCall,
      size: size,
      safeArea: safeArea,
      locale: locale,
    );
    await pumpMs(tester, 800); // intro + both button groups
  }

  testWidgets('audio caller: name, blinking title, type, safety and buttons', (
    tester,
  ) async {
    await openIncoming(tester, callOf());

    expect(find.byType(IncomingCallScreen), findsOneWidget);
    expect(find.text('Ananya'), findsOneWidget);
    expect(find.text('INCOMING CALL...'), findsOneWidget);
    expect(find.text('Audio Call'), findsOneWidget);
    expect(find.text('Block this caller'), findsOneWidget);
    expect(find.text('Declines and stops them contacting you'), findsOneWidget);
    expect(find.text('Report this caller'), findsOneWidget);
    expect(find.text('DECLINE'), findsOneWidget);
    expect(find.text('ACCEPT'), findsOneWidget);
    expect(find.text('App Official'), findsNothing);

    // Buttons sit above the home indicator area, the card above them.
    final accept = tester.getRect(_pressable('Accept'));
    expect(accept.bottom, lessThan(se.height));
    expect(
      tester.getRect(find.text('Report this caller')).bottom,
      lessThan(accept.top),
    );
    expect(tester.takeException(), isNull);
    await finishCall(tester);
  });

  testWidgets('video caller and company caller', (tester) async {
    await openIncoming(
      tester,
      callOf(video: true, company: true),
      size: proMax,
      safeArea: proMaxInsets,
    );

    expect(find.text('Video Call'), findsOneWidget);
    // Top white pill + chip under the name.
    expect(find.text('App Official'), findsNWidgets(2));
    expect(find.byIcon(Icons.verified), findsNWidgets(2));
    // The top pill clears the Dynamic Island.
    expect(
      tester.getRect(find.text('App Official').first).top,
      greaterThan(proMaxInsets.top),
    );
    expect(tester.takeException(), isNull);
    await finishCall(tester);
  });

  testWidgets('decline is held for 2.5 s, accept never is', (tester) async {
    await openIncoming(tester, callOf());

    Pressable button(String label) =>
        tester.widget<Pressable>(_pressable(label));
    expect(button('Decline').onPressed, isNull);
    expect(button('Accept').onPressed, isNotNull);

    await pumpMs(tester, 1800); // 2.6 s after mount
    expect(button('Decline').onPressed, isNotNull);
    await finishCall(tester);
  });

  testWidgets('answered (here or elsewhere) → the call screen', (tester) async {
    await openIncoming(tester, callOf());
    await setCall(tester, callOf(phase: CallPhase.accepted));
    await pumpMs(tester, 100);

    expect(find.byType(IncomingCallScreen), findsNothing);
    expect(find.byType(CallScreen), findsOneWidget);
    await finishCall(tester);
  });

  testWidgets('block asks first', (tester) async {
    await openIncoming(tester, callOf());

    await tester.tap(find.text('Block this caller'));
    await pumpMs(tester, 300);
    expect(find.text('Block Ananya?'), findsOneWidget);
    expect(
      find.text(
        'The call will be declined and they will not be able to contact you '
        'again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('CANCEL'));
    await pumpMs(tester, 300);
    expect(find.text('Block Ananya?'), findsNothing);
    await finishCall(tester);
  });

  for (final (label, locale, name) in const [
    ('long name', Locale('en'), 'Venkata Lakshmi Narasimha Subrahmanyam'),
    ('Hindi', Locale('hi'), 'अनन्या कृष्णमूर्ति शर्मा'),
  ]) {
    testWidgets('320 wide, $label: no overflow', (tester) async {
      await openIncoming(
        tester,
        callOf(name: name, video: true, company: true),
        size: narrow,
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text(name), findsOneWidget);
      await finishCall(tester);
    });
  }

  testWidgets('a different ring re-arms the decline guard (U11)', (
    tester,
  ) async {
    await openIncoming(tester, callOf());
    Pressable decline() => tester.widget<Pressable>(_pressable('Decline'));
    await pumpMs(tester, 1800);
    expect(decline().onPressed, isNotNull);

    await setCall(tester, callOf(callId: '502', name: 'Meera'));
    expect(find.text('Meera'), findsOneWidget);
    expect(decline().onPressed, isNull);
    await pumpMs(tester, 2500);
    expect(decline().onPressed, isNotNull);
    await finishCall(tester);
  });

  testWidgets('block confirmed after the ring ended still files (U2)', (
    tester,
  ) async {
    await openIncoming(tester, callOf());
    await tester.tap(find.text('Block this caller'));
    await pumpMs(tester, 300);
    expect(find.text('Block Ananya?'), findsOneWidget);

    // The caller gives up while the confirm is open.
    await setCall(tester, CallSession.idle);
    await tester.tap(find.text('BLOCK'));
    await pumpMs(tester, 300);
    expect(backend.requests, contains('POST /api/user-blocks'));
    expect(tester.takeException(), isNull);
    await finishCall(tester);
  });

  for (final (label, size, locale, name) in const [
    ('375×667 Hindi', se, Locale('hi'), _hindiName),
    ('320×568 Hindi', _iphone5, Locale('hi'), _hindiName),
    (
      '320×568 long name',
      _iphone5,
      Locale('en'),
      'Venkata Lakshmi Narasimha Subrahmanyam',
    ),
  ]) {
    testWidgets('$label: the intro never runs into the actions (U7)', (
      tester,
    ) async {
      await openIncoming(
        tester,
        callOf(name: name, video: true, company: true),
        size: size,
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      // Two lines of 36 px name.
      expect(tester.getSize(find.text(name)).height, greaterThan(70));

      final card = tester.getRect(find.byType(IncomingSafetyCard));
      final actions = tester.getRect(find.byType(IncomingActions));
      // The last line of the intro (call type) ends clearly above the card.
      expect(_introBottom(tester) + 4, lessThan(card.top));
      expect(actions.bottom, lessThanOrEqualTo(size.height));
      // Below the top "App Official" pill.
      expect(
        tester.getRect(find.byType(CallAvatarRing)).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(IncomingOfficialPill)).bottom,
        ),
      );
      await finishCall(tester);
    });
  }

  testWidgets('large phone keeps RN geometry (U7)', (tester) async {
    await openIncoming(tester, callOf(), size: proMax, safeArea: proMaxInsets);
    final vs = proMax.height / 812;
    // Avatar at safe top + vs120 (+ the intro's vs16), actions end vs80
    // above the screen bottom.
    expect(
      tester.getRect(find.byType(CallAvatarRing)).top,
      moreOrLessEquals(proMaxInsets.top + 136 * vs, epsilon: 0.5),
    );
    expect(
      tester.getRect(find.byType(IncomingActions)).bottom,
      moreOrLessEquals(proMax.height - 80 * vs, epsilon: 0.5),
    );
    expect(
      _introBottom(tester),
      lessThan(tester.getRect(find.byType(IncomingSafetyCard)).top),
    );
    await finishCall(tester);
  });
}
