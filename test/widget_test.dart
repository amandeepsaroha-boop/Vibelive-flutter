import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/component/app_logo.dart';
import 'package:vibelive/app/splashscreen/onboarding_view.dart';
import 'package:vibelive/app/splashscreen/splash_motion.dart';
import 'package:vibelive/app/splashscreen/splash_screen.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';

/// Offline backend: every request fails at once (no pending timers).
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'offline in tests',
  );

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    VibeLiveApp(
      themeController: ThemeController(ThemeMode.dark),
      localeController: LocaleController(locale),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Advances past animations that never settle (the onboarding loops).
Future<void> _wait(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts and lets fquery's 5-minute cache GC timers fire.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}

void main() {
  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    await AppPrefs.init();
    ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
    ApiClient.dio.httpClientAdapter = _Offline();
  });

  // rootBundle caches asset futures per test zone; a stale cache leaves the
  // i18next delegate loading forever in the next test.
  setUp(() {
    rootBundle.clear();
    queryCache.clear();
  });

  testWidgets('splash shows the animated logo, then onboarding', (
    tester,
  ) async {
    await _pumpApp(tester);
    expect(find.byType(AppLogo), findsNWidgets(2)); // the two halves
    expect(find.byType(SplashLogo), findsOneWidget);
    expect(find.byType(OnboardingView), findsNothing);

    await _wait(tester, 2500 + 900);
    expect(find.byType(OnboardingView), findsOneWidget);
    expect(find.text('TALK IT THROUGH.'), findsOneWidget);
    // Offline: the topic marquee falls back to the bundled topics.
    expect(find.text('Dating advice'), findsWidgets);
    await _finish(tester);
  });

  testWidgets('continue, swipe back, skip leaves the splash', (tester) async {
    await _pumpApp(tester);
    await _wait(tester, 2500 + 900);

    await tester.tap(find.text('CONTINUE'));
    await _wait(tester, 700);
    expect(find.text('PAY BY THE MINUTE.'), findsOneWidget);

    await tester.fling(find.byType(OnboardingView), const Offset(300, 0), 1000);
    await _wait(tester, 700);
    expect(find.text('TALK IT THROUGH.'), findsOneWidget);

    await tester.tap(find.text('SKIP'));
    await _wait(tester, 700);
    expect(find.byType(SplashScreen), findsNothing);
    await _finish(tester);
  });

  testWidgets('Hindi translations and namespaces resolve', (tester) async {
    await _pumpApp(tester, locale: const Locale('hi'));
    final context = tester.element(find.byType(AppLogo).first);
    expect(context.t('actions.ok'), 'ठीक है');
    expect(context.t('common:actions.cancel'), 'रद्द करें');
    expect(context.t('splash:skip'), 'छोड़ें');
    expect(
      context.t('banner:warn.personal', variables: {'fields': 'नाम'}),
      contains('नाम'),
    );
    await _finish(tester);
  });
}
