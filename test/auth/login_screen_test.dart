import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/authscreen/helper/sms_otp_autofill.dart';
import 'package:vibelive/app/authscreen/login_screen.dart';
import 'package:vibelive/app/authscreen/widgets/auth_theme.dart';
import 'package:vibelive/app/authscreen/widgets/login_form_step.dart';
import 'package:vibelive/app/authscreen/widgets/login_otp_step.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// Backend stub: OTP requests answer from [otpReplies] (then succeed), every
/// code is rejected.
class _Backend implements HttpClientAdapter {
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];
  final otpReplies = <(int, Map<String, Object?>)>[];

  /// Set by a test: runs as each request arrives.
  void Function(String path)? onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    bodies.add(o.data is Map ? Map<String, dynamic>.from(o.data as Map) : {});
    onRequest?.call(o.path);
    final (status, body) = switch (o.path) {
      '/api/session-auth/otp/request' =>
        otpReplies.isEmpty ? (200, {'success': true}) : otpReplies.removeAt(0),
      '/api/session-auth/otp/verify' => (
        400,
        {
          'error': {'message': 'That code is not valid'},
        },
      ),
      '/api/user-referrals' => (200, {'data': <Object>[]}),
      _ => (404, <String, Object>{}),
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Android SMS Retriever + phone hint, driven by the test.
class _FakeSms extends SmsOtpAutofill {
  ValueChanged<String>? onCode;
  var starts = 0;
  String? hint;

  @override
  bool get isSupported => true;

  @override
  VoidCallback listen(ValueChanged<String> onCode) {
    starts++;
    this.onCode = onCode;
    return () => this.onCode = null;
  }

  @override
  Future<String?> requestPhoneHint() async => hint;

  @override
  Future<List<String>> appHashes() async => const [];
}

/// The test font is wider than the real one: scroll the target into view.
/// The sheet comes after the options page, so `.last` is the sheet's copy.
Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pump();
  await tester.tap(find.text(text).last);
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _formField() => find.descendant(
  of: find.byType(LoginFormStep),
  matching: find.byType(TextField),
);

Finder _codeField() => find.descendant(
  of: find.byType(LoginOtpStep),
  matching: find.byType(TextField),
);

/// Text inside the sheet's current step (the options page behind it shows
/// the same error, as in RN).
Finder _inForm(String text) =>
    find.descendant(of: find.byType(LoginFormStep), matching: find.text(text));

Finder _termsBox() => find.descendant(
  of: find.byKey(const ValueKey('login-terms')),
  matching: find.byType(AnimatedContainer),
);

Future<void> _tickTerms(WidgetTester tester) async {
  await tester.ensureVisible(_termsBox());
  await _pump(tester, 100);
  await tester.tap(_termsBox());
  await tester.pump();
}

void main() {
  late _Backend backend;

  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
    // Platform replies never arrive under fake time: answer in Dart.
    PackageInfo.setMockInitialValues(
      appName: 'Vibe Live',
      packageName: 'com.angrymamba.vibelive',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await AppPrefs.init();
    ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
  });

  setUp(() {
    rootBundle.clear();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
  });

  /// [size]: logical viewport (default iPhone 14, not the 800x600 test
  /// default); [top] / [bottom]: notch and home-indicator insets.
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double top = 47,
    double bottom = 34,
    bool dark = true,
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3
      ..padding = FakeViewPadding(top: top * 3, bottom: bottom * 3)
      ..viewPadding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
    addTearDown(tester.view.reset);
    Scale.update(size); // the app root does this
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [AppI18n.delegate],
        home: const LoginScreen(),
      ),
    );
    await _pump(tester, 600);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, 1200); // pending debounce / unlock timers
  }

  /// Mobile sheet → valid number → terms → code step.
  Future<void> toCodeStep(WidgetTester tester) async {
    await _tap(tester, 'Continue with mobile number');
    await _pump(tester, 400);
    await tester.enterText(_formField(), '9876543210');
    await _tickTerms(tester);
    await _tap(tester, 'Send OTP');
    await _pump(tester, 300);
  }

  testWidgets('options page: headline, Google, mobile, email, legal', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Good\nconversations\nlive here.'), findsOneWidget);
    expect(find.text('Call. Connect.\nAnytime, anywhere.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with mobile number'), findsOneWidget);
    expect(find.text('Use email instead'), findsOneWidget);
    expect(
      find.text(
        'By continuing, you agree to our\nTerms & Conditions and '
        'Privacy Policy.',
      ),
      findsOneWidget,
    );
    expect(find.byType(LoginFormStep), findsNothing);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, AuthTheme.darkTheme.bg);
    await close(tester);
  });

  testWidgets('light theme uses the light sign-in palette', (tester) async {
    await open(tester, dark: false);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, AuthTheme.lightTheme.bg);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('mobile sheet: validation, terms nudge, then the code step', (
    tester,
  ) async {
    await open(tester);
    await _tap(tester, 'Continue with mobile number');
    await _pump(tester, 400);
    expect(find.text('Enter your\nmobile number'), findsOneWidget);
    expect(find.text("We'll text you a 4-digit code."), findsOneWidget);

    await tester.enterText(_formField(), '12345');
    await _tap(tester, 'Send OTP');
    await _pump(tester, 100);
    expect(_inForm('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(backend.requests, isEmpty);

    // A valid number, but the box is unticked: the checkbox row turns red.
    await tester.enterText(_formField(), '9876543210');
    await _tap(tester, 'Send OTP');
    await _pump(tester, 100);
    expect(
      find.text('Please accept the Terms & Conditions to continue'),
      findsOneWidget,
    );
    expect(backend.requests, isEmpty);

    await _tickTerms(tester);
    expect(
      find.text('Please accept the Terms & Conditions to continue'),
      findsNothing,
    );
    await _tap(tester, 'Send OTP');
    await _pump(tester, 300);
    expect(backend.requests, ['POST /api/session-auth/otp/request']);
    expect(backend.bodies.last['identifier'], '9876543210');
    expect(backend.bodies.last['channel'], 'sms');
    expect(find.text('Enter the\n4-digit code'), findsOneWidget);
    expect(find.text('Sent to +91 98765 43210  Change'), findsOneWidget);
    expect(find.text("Didn't get it? Resend in 30s"), findsOneWidget);
    await _pump(tester, 1000);
    expect(find.text("Didn't get it? Resend in 29s"), findsOneWidget);

    // Back (header) returns to the form, the number is kept.
    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await _pump(tester, 300);
    expect(find.text('Enter your\nmobile number'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);

    // Close: back to the options.
    await tester.tap(find.byIcon(LucideIcons.x));
    await _pump(tester, 400);
    expect(find.byType(LoginFormStep), findsNothing);
    await close(tester);
  });

  testWidgets('email: a rejected code shows the server message inline', (
    tester,
  ) async {
    await open(tester);
    await _tap(tester, 'Use email instead');
    await _pump(tester, 400);
    expect(find.text('Enter your\nemail address'), findsOneWidget);
    await tester.enterText(_formField(), 'not-an-email');
    await _tap(tester, 'Send OTP');
    await _pump(tester, 100);
    expect(_inForm('Enter a valid email address'), findsOneWidget);

    await tester.enterText(_formField(), 'Tester@Mail.com');
    await _tickTerms(tester);
    await _tap(tester, 'Send OTP');
    await _pump(tester, 300);
    expect(backend.bodies.last['identifier'], 'tester@mail.com');
    expect(backend.bodies.last['channel'], 'email');
    expect(find.text('Sent to te***@mail.com  Change'), findsOneWidget);

    // Four digits auto-verify; the boxes clear for the next attempt.
    await tester.enterText(_codeField(), '1234');
    await _pump(tester, 400);
    expect(backend.requests.last, 'POST /api/session-auth/otp/verify');
    expect(backend.bodies.last['code'], '1234');
    expect(
      find.descendant(
        of: find.byType(LoginOtpStep),
        matching: find.text('That code is not valid'),
      ),
      findsOneWidget,
    );
    expect(find.text('Verification Failed'), findsNothing); // no alert (RN)
    expect(tester.widget<TextField>(_codeField()).controller!.text, isEmpty);
    await close(tester);
  });

  testWidgets('a 429 for the number that has a code reopens that code', (
    tester,
  ) async {
    await open(tester);
    await toCodeStep(tester);
    expect(find.text("Didn't get it? Resend in 30s"), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await _pump(tester, 300);
    backend.otpReplies.add((
      429,
      {
        'error': {
          'message': 'Too many attempts, wait a bit.',
          'details': {'retryAfter': 20},
        },
      },
    ));
    await _tap(tester, 'Send OTP');
    await _pump(tester, 300);
    expect(find.byType(LoginOtpStep), findsOneWidget);
    expect(find.text("Didn't get it? Resend in 20s"), findsOneWidget);
    expect(find.text('Too many attempts, wait a bit.'), findsNothing);

    // Another number in the cooldown: the server's message, no code step.
    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await _pump(tester, 300);
    await tester.enterText(_formField(), '9123456780');
    backend.otpReplies.add((
      429,
      {
        'error': {
          'message': 'Too many attempts, wait a bit.',
          'details': {'retryAfter': 20},
        },
      },
    ));
    await _tap(tester, 'Send OTP');
    await _pump(tester, 300);
    expect(find.byType(LoginOtpStep), findsNothing);
    expect(find.text('Too many attempts, wait a bit.'), findsWidgets);
    await close(tester);
  });

  testWidgets('Android back: code → form → options', (tester) async {
    await open(tester);
    await toCodeStep(tester);
    expect(find.byType(LoginOtpStep), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _pump(tester, 300);
    expect(find.byType(LoginFormStep), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _pump(tester, 400);
    expect(find.byType(LoginFormStep), findsNothing);
    await close(tester);
  });

  testWidgets('SMS auto-fill: armed before the request, code verifies', (
    tester,
  ) async {
    final sms = _FakeSms()..hint = '+91 98765 43210';
    SmsOtpAutofill.instance = sms;
    addTearDown(() => SmsOtpAutofill.instance = const NoSmsOtpAutofill());
    var armedAtRequest = false;

    await open(tester);
    backend.onRequest = (path) {
      if (path.endsWith('/otp/request')) armedAtRequest = sms.onCode != null;
    };
    await _tap(tester, 'Continue with mobile number');
    await _pump(tester, 400);
    // The empty field took focus: the SIM-number picker filled it.
    expect(
      tester.widget<TextField>(_formField()).controller!.text,
      '9876543210',
    );

    await _tickTerms(tester);
    await _tap(tester, 'Send OTP');
    await _pump(tester, 300);
    expect(sms.starts, 1);
    expect(armedAtRequest, isTrue);

    sms.onCode!('4821');
    await _pump(tester, 400);
    expect(backend.requests.last, 'POST /api/session-auth/otp/verify');
    expect(backend.bodies.last['code'], '4821');
    await close(tester);
  });

  /// Keyboard up on an iPhone SE: the engine reports the keyboard as a view
  /// inset, and the bottom safe-area padding drops to 0.
  void showKeyboard(WidgetTester tester) {
    tester.view
      ..viewInsets = const FakeViewPadding(bottom: 300 * 3)
      ..padding = const FakeViewPadding(top: 20 * 3);
  }

  /// Visible area above the keyboard, in logical pixels.
  const se = Size(375, 667);
  const keyboardTop = 667.0 - 300;

  void expectAboveKeyboard(WidgetTester tester, Finder finder) {
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(20), reason: '$finder under notch');
    expect(rect.bottom, lessThanOrEqualTo(keyboardTop), reason: '$finder');
  }

  testWidgets('iPhone SE, keyboard open: fields and CTAs stay reachable', (
    tester,
  ) async {
    await open(tester, size: se, top: 20, bottom: 0);
    expect(tester.takeException(), isNull);

    // Referral field on the options page scrolls above the keyboard.
    await _tap(tester, 'Have a referral code?');
    await _pump(tester, 100);
    await tester.tap(find.byType(TextField).last);
    showKeyboard(tester);
    await _pump(tester, 400);
    expect(tester.takeException(), isNull);
    expectAboveKeyboard(tester, find.byType(TextField).last);
    tester.view.resetViewInsets();
    tester.view.padding = const FakeViewPadding(top: 20 * 3);
    await _pump(tester, 300);

    // Mobile sheet: the field takes focus, the sheet sits on the keyboard.
    await _tap(tester, 'Continue with mobile number');
    showKeyboard(tester);
    await _pump(tester, 400);
    expect(tester.takeException(), isNull); // no RenderFlex overflow
    expectAboveKeyboard(tester, _formField());

    await tester.enterText(_formField(), '9876543210');
    await _pump(tester, 300); // caret scroll-into-view settles
    await _tickTerms(tester);
    await tester.ensureVisible(find.text('Send OTP'));
    await _pump(tester, 100);
    expectAboveKeyboard(tester, find.text('Send OTP'));
    await tester.tap(find.text('Send OTP'));
    await _pump(tester, 300);
    expect(find.byType(LoginOtpStep), findsOneWidget);

    // Code step: the code field takes focus, the boxes and Verify are
    // above the keyboard.
    showKeyboard(tester);
    await _pump(tester, 400);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: _codeField(),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expectAboveKeyboard(tester, _codeField());
    await tester.ensureVisible(find.text('Verify'));
    await _pump(tester, 100);
    expectAboveKeyboard(tester, find.text('Verify'));
    await close(tester);
  });

  testWidgets('320 x 568, keyboard closed and open: no overflow', (
    tester,
  ) async {
    await open(tester, size: const Size(320, 568), top: 20, bottom: 0);
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260 * 3);
    await _pump(tester, 400);
    expect(tester.takeException(), isNull);

    // The sheet and both steps fit above a 260 px keyboard.
    await _tap(tester, 'Use email instead');
    await _pump(tester, 400);
    expect(tester.takeException(), isNull);
    await tester.enterText(_formField(), 'a@b.co');
    await _pump(tester, 300); // caret scroll-into-view settles
    await _tickTerms(tester);
    await tester.ensureVisible(find.text('Send OTP'));
    await _pump(tester, 100);
    expect(tester.getRect(find.text('Send OTP')).bottom, lessThan(568 - 260));
    await tester.tap(find.text('Send OTP'));
    await _pump(tester, 400);
    expect(find.byType(LoginOtpStep), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Verify'));
    await _pump(tester, 100);
    expect(tester.getRect(find.text('Verify')).bottom, lessThan(568 - 260));
    await close(tester);
  });

  testWidgets('referral link opens the code field, which validates', (
    tester,
  ) async {
    await open(tester);
    await _tap(tester, 'Have a referral code?');
    await _pump(tester, 100);
    expect(find.text('Referral code (optional)'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'abc12');
    expect(find.text('ABC12'), findsOneWidget);
    await _pump(tester, 1000); // 800 ms debounce, then the lookup
    expect(backend.requests.last, 'GET /api/user-referrals');
    expect(find.text('Invalid referral code'), findsOneWidget);
    await close(tester);
  });
}
