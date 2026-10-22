import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibelive/app/resourcesscreen/helper/resource_links.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';

/// Fake backend for the Resources screens: CMS pages, app-config, the
/// host's categories. Every reply takes [latency], so first loads show
/// their skeleton.
class ResourcesBackend implements HttpClientAdapter {
  final requests = <String>[];
  final puts = <Map>[];
  Duration latency = const Duration(milliseconds: 300);

  /// False: the signed-in user is a client (no expert on `/public-users`).
  bool isHost = true;

  /// `/page-contents?slug=` answers 400 while true.
  bool failPages = false;

  final menu = <Map<String, Object?>>[
    {'id': 1, 'slug': 'privacy-policy', 'title': 'Privacy Policy'},
    {'id': 2, 'slug': 'terms-and-conditions', 'title': 'Terms'},
  ];

  final pages = <String, Map<String, Object?>>{
    'privacy-policy': {
      'id': 1,
      'documentId': 'p1',
      'slug': 'privacy-policy',
      'title': 'Privacy Policy',
      'content':
          '<h2>Your data</h2><p>We keep it <strong>safe</strong>. '
          'Read <a href="https://vibe.example/policy">the full policy</a>.</p>'
          '<ul><li>No selling</li><li>No spam</li></ul>',
    },
    'about-app': {
      'id': 3,
      'slug': 'about-app',
      'title': 'About Vibe Live',
      'content': [
        {
          'type': 'paragraph',
          'children': [
            {'type': 'text', 'text': 'Talk to experts, live.'},
          ],
        },
      ],
    },
  };

  static const hostUser = {
    'id': 2,
    'documentId': 'u-host',
    'name': 'Riya',
    'email': 'r@b.co',
    'mobile': '9999999998',
  };

  static const hostExpert = {'id': 5, 'documentId': 'exp1', 'handler': 'riya'};

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    await Future<void>.delayed(latency);
    final (status, body) = _reply(o);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  /// Writes other than the categories PUT: `METHOD path` → body.
  final writes = <String, Object?>{};

  bool blockedEmpty = false;

  (int, Object) _reply(RequestOptions o) {
    final q = o.queryParameters;
    if (o.method != 'GET' && o.path != '/api/expert-profiles/exp1') {
      writes['${o.method} ${o.path}'] = o.data;
      if (o.path == '/api/user-blocks/unblock') blockedEmpty = true;
      if (o.path == '/api/gst-details') {
        return (
          200,
          {
            'data': {'id': 9, 'documentId': 'gst1'},
          },
        );
      }
      return (200, {'data': <String, Object?>{}});
    }
    if (o.method == 'PUT' && o.path == '/api/expert-profiles/exp1') {
      puts.add((o.data as Map)['data'] as Map);
      return (200, {'data': hostExpert});
    }
    switch (o.path) {
      case '/api/page-contents' when q.containsKey(r'filters[slug][$eq]'):
        if (failPages) {
          return (
            400,
            {
              'error': {'message': 'Bad page request'},
            },
          );
        }
        final page = pages[q[r'filters[slug][$eq]']];
        return (
          200,
          {
            'data': page == null ? <Object>[] : [page],
          },
        );
      case '/api/page-contents':
        return (200, {'data': menu});
      case '/api/app-config':
        return (
          200,
          {
            'data': {
              'support_email': 'help@vibe.example',
              'support_phone': '+91 98765 43210',
            },
          },
        );
      case '/api/public-users/u-host':
        return (
          200,
          {
            'data': {
              ...hostUser,
              'platform': {'id': 2, 'name': 'Vibe'},
              if (isHost)
                'expert': {
                  ...hostExpert,
                  'categories': [
                    {'id': 11, 'name': 'Astrology'},
                  ],
                },
            },
          },
        );
      case '/api/categories':
        return (
          200,
          {
            'data': [
              {'id': 11, 'name': 'Astrology'},
              {'id': 12, 'name': 'Career'},
              {'id': 13, 'name': 'Yoga'},
            ],
            'meta': {
              'pagination': {'page': 1, 'pageCount': 1},
            },
          },
        );
      case '/api/expert-profiles/exp1':
        return (200, {'data': hostExpert});
      case '/api/favorites':
        return (
          200,
          {
            'data': [
              {
                'id': 7,
                'documentId': 'fav1',
                'experts': [
                  {
                    'id': 8,
                    'documentId': 'exp8',
                    'handler': 'meera',
                    'isVerified': true,
                    'user': {'id': 9, 'documentId': 'u9', 'name': 'Meera'},
                  },
                ],
              },
            ],
          },
        );
      case '/api/user-blocks':
        return (
          200,
          {
            'data': blockedEmpty
                ? <Object>[]
                : [
                    {
                      'blockedAt': '2026-03-01T10:00:00.000Z',
                      'user': {
                        'id': 4,
                        'documentId': 'u4',
                        'name': 'Kabir',
                        'role': 'Client',
                      },
                    },
                  ],
          },
        );
      case '/api/states':
        return (
          200,
          {
            'data': [
              {'id': 21, 'documentId': 's21', 'name': 'Delhi'},
            ],
          },
        );
    }
    return (200, {'data': <Object>[]});
  }

  @override
  void close({bool force = false}) {}
}

/// Records what the screens asked [ResourceLinks] to open.
class FakeOpener {
  final opened = <(Uri, LaunchMode)>[];
  bool result = true;

  Future<bool> call(Uri uri, LaunchMode mode) async {
    opened.add((uri, mode));
    return result;
  }
}

Future<void> pumpFor(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// One-time platform mocks (prefs, secure storage, package info).
Future<void> setUpResourcesSuite() async {
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

/// Fresh backend, cache and link opener for each test.
(ResourcesBackend, FakeOpener) setUpResourcesTest() {
  rootBundle.clear();
  queryCache.clear();
  final backend = ResourcesBackend();
  ApiClient.dio.httpClientAdapter = backend;
  final opener = FakeOpener();
  ResourceLinks.opener = opener.call;
  addTearDown(ResourceLinks.reset);
  return (backend, opener);
}

/// Signs the host in, pumps the app and goes to [route].
Future<void> openRoute(
  WidgetTester tester,
  String route, {
  ThemeMode theme = ThemeMode.dark,
  Size size = const Size(390, 844),
  Locale locale = const Locale('en'),
  double bottomInset = 0,
  bool host = true,
}) async {
  await SessionStore.instance.signIn(
    user: Map<String, dynamic>.from(ResourcesBackend.hostUser),
    expert: host
        ? Map<String, dynamic>.from(ResourcesBackend.hostExpert)
        : null,
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
  appRouter.go(route);
  await tester.pump();
  await tester.pump();
}

/// Unmounts and lets fquery's GC timers run out.
Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}

/// Where the user is: the pushed page's location when there is one (a
/// push does not change the router's base URI).
String get location {
  final config = appRouter.routerDelegate.currentConfiguration;
  final last = config.last;
  return last is ImperativeRouteMatch
      ? last.matches.uri.toString()
      : config.uri.toString();
}
