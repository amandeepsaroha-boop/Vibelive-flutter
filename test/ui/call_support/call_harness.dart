// Shared setup of the call UI tests (`test/ui/call_*_test.dart`).
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fquery/fquery.dart' show CacheProvider;
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/callscreen/call/call_overlay_host.dart';
import 'package:vibelive/app/callscreen/call/call_screen.dart';
import 'package:vibelive/app/callscreen/call/incoming_call_screen.dart';
import 'package:vibelive/app/callscreen/call/return_to_call_bar.dart';
import 'package:vibelive/app/callscreen/helper/call_controller.dart';
import 'package:vibelive/app/callscreen/helper/call_session.dart';
import 'package:vibelive/app/callscreen/helper/call_signals.dart';
import 'package:vibelive/app/callscreen/helper/engine/call_engine.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// iPhone SE (2nd/3rd gen), iPhone 15 Pro Max, and a 320-wide phone.
const se = Size(375, 667);
const proMax = Size(430, 932);
const narrow = Size(320, 640);
const seInsets = EdgeInsets.only(top: 20);
const proMaxInsets = EdgeInsets.only(top: 59, bottom: 34);

/// A fake backend: the callback host lookup, everything else empty.
class CallBackend implements HttpClientAdapter {
  final requests = <String>[];

  /// While set, every answer waits for it (a slow network).
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    await gate?.future;
    final Object body = o.path == '/api/expert-profiles'
        ? {
            'data': [
              {
                'id': 7,
                'documentId': 'exp7',
                'rates': {'videoCallRate': 30, 'voiceCallRate': 20},
                'user': {'id': 70, 'documentId': 'usr7', 'name': 'Meera'},
              },
            ],
          }
        : {'data': <Object>[]};
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

/// Mocks the plugins every test needs, once.
Future<void> callSetUpAll() async {
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

/// Per test: a clean cache, the fake backend, a signed-in user (id 1).
Future<CallBackend> callSetUp() async {
  rootBundle.clear();
  queryCache.clear();
  final backend = CallBackend();
  ApiClient.dio.httpClientAdapter = backend;
  await SessionStore.instance.signIn(
    user: {
      'id': 1,
      'documentId': 'u1',
      'name': 'Asha',
      'email': 'a@b.co',
      'mobile': '9999999999',
    },
    accessToken: 'access',
  );
  return backend;
}

/// A call as the logic would publish it.
CallSession callOf({
  String callId = '501',
  CallPhase phase = CallPhase.ringing,
  CallRole role = CallRole.receiver,
  bool video = false,
  String? name = 'Ananya',
  bool company = false,
  bool callerCompany = false,
  DateTime? connectedAt,
  DateTime? endedAt,
  DateTime? phaseSince,
}) => CallSession(
  phase: phase,
  role: role,
  callId: callId,
  channelName: 'call_1_70_1',
  isVideo: video,
  remote: CallPeer(id: '70', name: name, isCompany: company),
  callerId: role == CallRole.caller ? '1' : '70',
  receiverId: role == CallRole.caller ? '70' : '1',
  callerIsCompany: callerCompany,
  connectedAt: connectedAt,
  endedAt: endedAt,
  phaseSince: phaseSince,
);

/// Publishes [session] (and optionally [media]) and lets the UI catch up.
Future<void> setCall(
  WidgetTester tester,
  CallSession session, {
  CallMedia? media,
}) async {
  if (media != null) CallEngine.instance.debugSetMedia(media);
  CallController.instance.debugSet(session);
  await pumpMs(tester, 100);
}

Future<void> pumpMs(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Mounts the call routes (and a Home stand-in with the return bar) at
/// [initial], on a phone of [size] with [safeArea] insets.
Future<GoRouter> pumpCallApp(
  WidgetTester tester, {
  String initial = AppRoutes.call,
  Size size = se,
  EdgeInsets safeArea = seInsets,
  Locale locale = const Locale('en'),
  ValueNotifier<CallbackRequest?>? callbacks,
  Widget? homeChild,
}) async {
  final insets = FakeViewPadding(
    top: safeArea.top * 3,
    bottom: safeArea.bottom * 3,
  );
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3
    ..padding = insets
    ..viewPadding = insets;
  addTearDown(tester.view.reset);
  Scale.update(size);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initial,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const ReturnToCallBar(),
                const Text('HOME PAGE'),
                ?homeChild,
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.call,
        pageBuilder: (_, state) =>
            NoTransitionPage(key: state.pageKey, child: const CallScreen()),
      ),
      GoRoute(
        path: AppRoutes.incomingCall,
        pageBuilder: (_, state) => NoTransitionPage(
          key: state.pageKey,
          child: const IncomingCallScreen(),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  final source = callbacks ?? ValueNotifier<CallbackRequest?>(null);
  await tester.pumpWidget(
    CacheProvider(
      cache: queryCache,
      child: MaterialApp.router(
        routerConfig: router,
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: AppTheme.dark(),
        locale: locale,
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [
          AppI18n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) => CallOverlayHost(
          requests: source,
          onConsumed: () => source.value = null,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await pumpMs(tester, 300);
  return router;
}

/// Unmounts, clears the call (stops the timer) and drains fquery's timers.
Future<void> finishCall(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  CallController.instance.debugSet(CallSession.idle);
  CallEngine.instance.debugSetMedia(CallMedia.initial);
  await tester.pump(const Duration(minutes: 6));
}

/// Counts rebuilds per widget type while [body] runs.
Future<Map<String, int>> countRebuilds(Future<void> Function() body) async {
  final counts = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final n = e.widget.runtimeType.toString();
    counts[n] = (counts[n] ?? 0) + 1;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}
