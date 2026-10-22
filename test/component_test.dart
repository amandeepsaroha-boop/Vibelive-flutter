import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/component/c_alert.dart';
import 'package:vibelive/app/component/c_button.dart';
import 'package:vibelive/app/component/c_input.dart';
import 'package:vibelive/app/component/c_text.dart';
import 'package:vibelive/app/component/exit_on_double_back.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// Minimal app shell with the real theme + i18n.
Widget _host(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: AppTheme.dark(),
  locale: locale,
  supportedLocales: AppI18n.supportedLocales,
  localizationsDelegates: [AppI18n.delegate],
  home: Scaffold(body: Center(child: child)),
);

void main() {
  setUp(rootBundle.clear);

  testWidgets('CText translates, uppercases by variant, ignores OS scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Column(
        children: [
          CText('actions.retry', variant: CTextVariant.caption),
          CText.raw('Rahul'),
        ],
      ).let(_host),
    );
    await tester.pumpAndSettle();
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.text('Rahul'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Rahul'));
    expect(text.textScaler, TextScaler.noScaling);
  });

  testWidgets('CButton debounces rapid taps and ignores taps while loading', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(CButton(title: 'actions.continue', onPressed: () => taps++)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CButton));
    await tester.tap(find.byType(CButton));
    expect(taps, 1);

    await tester.pumpWidget(
      _host(
        CButton(
          title: 'actions.continue',
          loading: true,
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(CButton), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('CInput mobile keeps digits only and shows translated error', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _host(
        CInput(
          type: CInputType.mobile,
          controller: controller,
          errorText: 'errors.rejected',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '98a76-5');
    expect(controller.text, '98765');
    expect(find.text('+91'), findsOneWidget);
    // Sentence case under the pill (RN InputBox), not the old caps label.
    expect(find.textContaining('check and try again'), findsOneWidget);
  });

  testWidgets('CAlert.confirm resolves true on confirm, and errors use copy', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(SizedBox));

    final result = CAlert.confirm(context: ctx, title: 'actions.confirm');
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONFIRM').last);
    await tester.pumpAndSettle();
    expect(await result, isTrue);

    unawaited(
      CAlert.error(const ApiException(ApiErrorType.network), context: ctx),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No internet connection'), findsOneWidget);
  });

  testWidgets('CInput mobile: a pasted / autofilled +91 or 0 number keeps '
      'the 10 digits; typing is never rewritten', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _host(
        CInput(type: CInputType.mobile, controller: controller, maxLength: 10),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.enterText(field, '+91 98765 43210');
    expect(controller.text, '9876543210');
    await tester.enterText(field, '09876543210');
    expect(controller.text, '9876543210');
    await tester.enterText(field, '919876543210');
    expect(controller.text, '9876543210');

    // Digit by digit, a number that starts with 91 stays as typed.
    await tester.enterText(field, '919876543');
    await tester.enterText(field, '9198765432');
    expect(controller.text, '9198765432');
  });

  testWidgets('CAlert sits above the keyboard; a long message scrolls', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(375, 667) * 3
      ..devicePixelRatio = 3
      ..viewInsets = const FakeViewPadding(bottom: 300 * 3);
    addTearDown(tester.view.reset);
    Scale.update(const Size(375, 667));
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pumpAndSettle();

    unawaited(
      CAlert.show(
        context: tester.element(find.byType(SizedBox)),
        title: 'Server says',
        message: List.filled(120, 'A very long server message.').join(' '),
        secondaryLabel: 'actions.cancel',
        translate: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no bottom overflow
    final ok = tester.getRect(find.text('OK'));
    expect(ok.bottom, lessThanOrEqualTo(667 - 300));
    expect(tester.getRect(find.text('Server says')).top, greaterThan(0));
  });

  testWidgets('ExitOnDoubleBack: onBack first, then press twice to exit', (
    tester,
  ) async {
    final exits = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var inner = true; // e.g. Home on another tab, login on the code step
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        scaffoldMessengerKey: scaffoldMessengerKey,
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [AppI18n.delegate],
        home: ExitOnDoubleBack(
          onBack: () {
            final used = inner;
            inner = false;
            return used;
          },
          child: const Scaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute(); // used by onBack
    await tester.pump();
    expect(find.text('Press back again to exit'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Press back again to exit'), findsOneWidget);
    expect(exits, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, ['SystemNavigator.pop']);
    await tester.pump(const Duration(seconds: 3)); // toast timer
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
