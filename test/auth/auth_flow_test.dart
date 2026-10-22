import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/authscreen/age_gate_screen.dart';
import 'package:vibelive/app/authscreen/login_screen.dart';
import 'package:vibelive/app/authscreen/widgets/login_form_step.dart';
import 'package:vibelive/app/authscreen/widgets/login_otp_step.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';

/// Backend for the whole sign-in path. [user] is what OTP verify returns.
class _Backend implements HttpClientAdapter {
  _Backend(this.user, {this.bypass = false});
  final Map<String, Object?> user;

  /// Whitelisted number: `/otp/request` signs in itself (no code).
  final bool bypass;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    calls.add(o.path);
    final Object body = switch (o.path) {
      '/api/session-auth/otp/request' =>
        bypass
            ? {
                'bypassed': true,
                'accessToken': 'access',
                'refreshToken': 'refresh',
                'user': user,
              }
            : {'success': true},
      '/api/session-auth/otp/verify' => {
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'user': user,
      },
      '/api/public-users/u1' => {'data': user},
      '/api/me' => user,
      // A form without the language question: the language step is done.
      '/api/interests/form' => {
        'data': {'questions': <Object>[]},
      },
      _ => {'data': <Object>[]},
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pump();
  await tester.tap(find.text(text).last);
}

void main() {
  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
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

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    rootBundle.clear();
    queryCache.clear();
    await SessionStore.instance.signOut();
    ApiClient.resetLogoutFlag();
    appRouter.go(AppRoutes.splash);
  });

  Future<void> signInThroughUi(
    WidgetTester tester,
    _Backend backend, {
    bool mobile = false,
  }) async {
    ApiClient.dio.httpClientAdapter = backend;
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.dark),
        localeController: LocaleController(const Locale('en')),
      ),
    );
    await _pump(tester, 2500 + 900); // splash → onboarding
    await _tap(tester, 'SKIP');
    await _pump(tester, 900);
    expect(find.byType(LoginScreen), findsOneWidget);

    await _tap(
      tester,
      mobile ? 'Continue with mobile number' : 'Use email instead',
    );
    await _pump(tester, 400);
    await tester.enterText(
      find.descendant(
        of: find.byType(LoginFormStep),
        matching: find.byType(TextField),
      ),
      mobile ? '9876543210' : 'a@b.co',
    );
    final terms = find.descendant(
      of: find.byKey(const ValueKey('login-terms')),
      matching: find.byType(AnimatedContainer),
    );
    await tester.ensureVisible(terms);
    await _pump(tester, 100);
    await tester.tap(terms);
    await _pump(tester, 100);
    await _tap(tester, 'Send OTP');
    await _pump(tester, 300);
    if (!backend.bypass) {
      await tester.enterText(
        find.descendant(
          of: find.byType(LoginOtpStep),
          matching: find.byType(TextField),
        ),
        '1234',
      ); // auto-verify
    }
    await _pump(tester, 1500);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  testWidgets('new user: OTP sign-in lands on the 18+ gate', (tester) async {
    final backend = _Backend({
      'id': 1,
      'documentId': 'u1',
      'email': 'a@b.co',
      'date_of_birth': null,
      'age_blocked': false,
    });
    await signInThroughUi(tester, backend);

    expect(backend.calls, contains('/api/session-auth/otp/verify'));
    expect(SessionStore.instance.value.userDocumentId, 'u1');
    expect(find.byType(AgeGateScreen), findsOneWidget);
    expect(find.text("What's your date of birth?"), findsOneWidget);
    await finish(tester);
  });

  testWidgets('returning user goes straight to Home; logout → login', (
    tester,
  ) async {
    final backend = _Backend({
      'id': 1,
      'documentId': 'u1',
      'email': 'a@b.co',
      'name': 'Asha',
      'date_of_birth': '1995-05-05',
    });
    await signInThroughUi(tester, backend);

    expect(
      appRouter.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.home,
    );

    // Session ends anywhere (logout, refresh failure) → the guard shows login.
    await SessionStore.instance.signOut();
    await _pump(tester, 600);
    expect(find.byType(LoginScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('whitelisted number: /otp/request signs in, no code step', (
    tester,
  ) async {
    final backend = _Backend({
      'id': 1,
      'documentId': 'u1',
      'phone': '9876543210',
      'name': 'Asha',
      'date_of_birth': '1995-05-05',
    }, bypass: true);
    await signInThroughUi(tester, backend, mobile: true);

    expect(backend.calls, isNot(contains('/api/session-auth/otp/verify')));
    expect(SessionStore.instance.value.userDocumentId, 'u1');
    expect(
      appRouter.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.home,
    );
    await finish(tester);
  });
}
