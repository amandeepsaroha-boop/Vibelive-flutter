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
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';

/// One recorded request.
typedef Call = ({String method, String path, Map<String, dynamic> query});

/// Fake Strapi for the referral screen and the ME invite card: a host with
/// a referral code, the users who joined with it, and the share counter.
class ReferralBackend implements HttpClientAdapter {
  final calls = <Call>[];

  /// `user_referral` of the signed-in user (null: no code).
  Map<String, Object?>? referral = {
    'referralCode': 'vibe42',
    'totalClicks': 7,
    'joinedUserCount': 2,
  };

  /// `/public-users?filters[referrerCode]…` rows.
  List<Map<String, Object?>> joined = [];

  /// The user read answers 404 this many more times.
  int userFailures = 0;

  /// The copy counter answers 400.
  bool copyFails = false;

  Iterable<Call> where(String path) => calls.where((c) => c.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    calls.add((method: o.method, path: o.path, query: o.queryParameters));
    var status = 200;
    Object body;
    if (o.path == '/api/public-users/u-host' && userFailures > 0) {
      userFailures--;
      status = 404;
      body = {
        'error': {'status': 404, 'message': 'Not Found'},
      };
    } else if (o.path == '/api/referral/VIBE42/copy') {
      if (copyFails) {
        status = 400;
        body = {
          'error': {'status': 400, 'message': 'Bad Request'},
        };
      } else {
        final clicks = (referral!['totalClicks'] as int) + 1;
        referral!['totalClicks'] = clicks;
        body = {'copyCount': clicks};
      }
    } else {
      body = _reply(o);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object _reply(RequestOptions o) => switch (o.path) {
    '/api/public-users/u-host' => {'data': hostUser()},
    '/api/public-users' => {'data': joined},
    '/api/expert-profiles/exp1' => {'data': expert()},
    _ => {'data': <Object>[]},
  };

  Map<String, Object?> expert() => {
    'id': 5,
    'documentId': 'exp1',
    'handler': 'riya',
    'isApproved': true,
    'isActive': true,
    'user_status': 'online',
    'vocationMode': false,
    'callAnyTime': true,
    'schedule': <Object>[],
    'expert_verifications': <Object>[],
  };

  Map<String, Object?> hostUser() => {
    'id': 2,
    'documentId': 'u-host',
    'name': 'Riya',
    'email': 'r@b.co',
    'mobile': '9999999998',
    'user_referral': referral == null ? null : {...referral!},
    'expert': expert(),
  };

  @override
  void close({bool force = false}) {}
}

Future<void> pumpMs(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Prefs, secure storage and package info mocks; quiet Dio.
Future<void> setUpReferralMocks() async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  FlutterSecureStorage.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'Vibe Live',
    packageName: 'com.angrymamba.vibelive',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  await AppPrefs.init();
  ApiClient.dio.interceptors.removeWhere((i) => i is PrettyDioLogger);
}

ReferralBackend installBackend() {
  rootBundle.clear();
  queryCache.clear();
  final backend = ReferralBackend();
  ApiClient.dio.httpClientAdapter = backend;
  return backend;
}

/// Signs the host in and opens [location] in the full app.
Future<void> openApp(
  WidgetTester tester,
  ReferralBackend backend, {
  required String location,
  ThemeMode theme = ThemeMode.dark,
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  double bottomInset = 0,
}) async {
  await SessionStore.instance.signIn(
    user: backend.hostUser()..remove('expert'),
    expert: backend.expert(),
    accessToken: 'access',
  );
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3
    ..padding = FakeViewPadding(bottom: bottomInset * 3)
    ..viewPadding = FakeViewPadding(bottom: bottomInset * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    VibeLiveApp(
      themeController: ThemeController(theme),
      localeController: LocaleController(locale),
    ),
  );
  appRouter.go(location);
  await tester.pump();
  await tester.pump();
}

/// Captures what the OS share sheet was given.
class ShareSpy {
  ShareSpy(WidgetTester tester) {
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'share') {
        final args = call.arguments as Map;
        text = args['text'] as String?;
        subject = args['subject'] as String?;
      }
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  String? text;
  String? subject;
}

/// Unmounts and lets fquery's GC timers run out.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}
