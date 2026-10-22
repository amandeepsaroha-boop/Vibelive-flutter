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
import 'package:vibelive/app/client/personal_info/helper/photo_source.dart';
import 'package:vibelive/app/client/personal_info/personal_info_screen.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/strapi.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// One recorded call.
typedef Call = ({String method, String path, Map query, Object? data});

const states = [
  {'id': 1, 'documentId': 'st-dl', 'name': 'Delhi'},
  {'id': 2, 'documentId': 'st-mh', 'name': 'Maharashtra'},
];

const districts = {
  'st-dl': [
    {'id': 11, 'documentId': 'd-nd', 'name': 'New Delhi'},
  ],
  'st-mh': [
    {'id': 21, 'documentId': 'd-pune', 'name': 'Pune'},
    {'id': 22, 'documentId': 'd-mum', 'name': 'Mumbai'},
  ],
};

/// A complete profile (Delhi / New Delhi), no photo.
JsonMap completeUser() => {
  'id': 1,
  'documentId': 'u1',
  'name': 'Asha Verma',
  'email': 'asha@b.co',
  'mobile': '9876543210',
  'state': states[0],
  'district': districts['st-dl']![0],
  'address_JSON': {'state': 'Delhi', 'district': 'New Delhi'},
};

/// Fake Strapi: the user (PUT applies the body like Strapi would), the
/// India country row, states and districts.
class PersonalInfoBackend implements HttpClientAdapter {
  PersonalInfoBackend(this.user);

  JsonMap user;
  final calls = <Call>[];

  /// Next PUT fails with a "must be unique" email error.
  bool emailTaken = false;

  Iterable<Call> where(String method, String path) =>
      calls.where((c) => c.method == method && c.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    calls.add((
      method: o.method,
      path: o.path,
      query: o.queryParameters,
      data: o.data,
    ));
    if (o.method == 'PUT' && emailTaken) {
      emailTaken = false;
      return _json({
        'error': {
          'status': 400,
          'name': 'ValidationError',
          'message': 'This attribute must be unique',
          'details': {
            'errors': [
              {
                'path': ['email'],
                'message': 'This attribute must be unique',
              },
            ],
          },
        },
      }, 400);
    }
    return _json(_reply(o), 200);
  }

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  Object _reply(RequestOptions o) {
    final q = o.queryParameters;
    if (o.path == '/api/public-users/u1' && o.method == 'PUT') {
      _apply(((o.data as Map)['data'] as Map).cast<String, dynamic>());
      return {'data': user};
    }
    switch (o.path) {
      case '/api/public-users/u1':
        return {'data': user};
      case '/api/countries':
        return {
          'data': [
            {'id': 99, 'documentId': 'c-in', 'name': 'India'},
          ],
        };
      case '/api/states':
        final term = '${q[r'filters[name][$containsi]'] ?? ''}'.toLowerCase();
        return {
          'data': [
            for (final s in states)
              if ('${s['name']}'.toLowerCase().contains(term)) s,
          ],
        };
      case '/api/districts':
        final id = q[r'filters[state][documentId][$eq]'];
        return {'data': districts[id] ?? const <Object>[]};
    }
    return {'data': <Object>[]};
  }

  void _apply(Map<String, dynamic> data) {
    JsonMap? find(List<Map<String, Object>> rows, Object? connect) {
      final id =
          (((connect as Map?)?['connect'] as List?)?.first as Map?)?['id'];
      return rows.where((r) => r['id'] == id).firstOrNull;
    }

    user = {
      ...user,
      for (final key in const ['name', 'email', 'mobile', 'address_JSON'])
        if (data.containsKey(key)) key: data[key],
      if (data.containsKey('state')) 'state': find(states, data['state']),
      if (data.containsKey('district'))
        'district': find([
          for (final list in districts.values) ...list,
        ], data['district']),
      if (data['profilePic'] != null)
        'profilePic': {
          'id': data['profilePic'],
          'url': 'https://cdn.test/${data['profilePic']}.jpg',
        },
    };
  }

  @override
  void close({bool force = false}) {}
}

/// The device picker and uploader, faked.
class FakePhotoSource extends PersonalInfoPhotoSource {
  final uploads = <String>[];
  String? next = '/tmp/picked.jpg';
  bool fail = false;

  @override
  Future<String?> pick() async {
    if (fail) throw StateError('no access');
    return next;
  }

  @override
  Future<JsonMap> upload(String path) async {
    uploads.add(path);
    return {'id': 501, 'url': '/uploads/new.jpg'};
  }
}

Future<void> pumpFor(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Mocks shared by every Personal Info test file.
void setUpPersonalInfoMocks() {
  setUpAll(() async {
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
  });
}

/// Signs [user] in, then shows a page with an OPEN button that pushes
/// Personal Info (like the ME tab, a call gate or "Become a Host").
/// [settle]: tap OPEN and wait for the profile.
Future<PersonalInfoBackend> openPersonalInfo(
  WidgetTester tester, {
  JsonMap? user,
  Size size = const Size(390, 844),
  ThemeMode theme = ThemeMode.dark,
  Locale locale = const Locale('en'),
  double bottomInset = 0,
  bool settle = true,
}) async {
  rootBundle.clear();
  queryCache.clear();
  // No disk copy of "my profile" from an earlier test.
  await QueryPersist.clearAll();
  final u = user ?? completeUser();
  final backend = PersonalInfoBackend(u);
  ApiClient.dio.httpClientAdapter = backend;
  await SessionStore.instance.signIn(user: {...u}, accessToken: 'access');

  final padding = FakeViewPadding(top: 20 * 3, bottom: bottomInset * 3);
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3
    ..padding = padding
    ..viewPadding = padding;
  addTearDown(tester.view.reset);
  Scale.update(size);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => context.push(AppRoutes.personalInfo),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.personalInfo,
        builder: (_, _) => const PersonalInfoScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    CacheProvider(
      cache: queryCache,
      child: MaterialApp.router(
        routerConfig: router,
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: theme,
        locale: locale,
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: [
          AppI18n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
      ),
    ),
  );
  await pumpFor(tester, 300);
  if (settle) {
    await tester.tap(find.text('OPEN'));
    await pumpFor(tester, 600);
  }
  return backend;
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 6));
}

/// The text inside the field with [key].
String fieldText(WidgetTester tester, String key) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

Future<void> enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    ),
    text,
  );
  await tester.pump();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}
