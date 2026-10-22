import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fquery/fquery.dart' show CacheProvider;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/listingflow/listing_queries.dart';
import 'package:vibelive/app/authscreen/helper/link_parser.dart';
import 'package:vibelive/app/callscreen/call/callback_sheet.dart';
import 'package:vibelive/app/callscreen/call/helper/callback_data.dart';
import 'package:vibelive/app/listingflow/profile/host_profile_sheet.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// A host's `/expert-profiles` row.
Map<String, Object?> _row(
  int id,
  String user,
  String name, {
  bool approved = true,
}) => {
  'id': id + 100,
  'documentId': 'exp-$user',
  'handler': name.toLowerCase().replaceAll(' ', '_'),
  'isApproved': approved,
  'isActive': true,
  'rates': {'videoCallRate': 30, 'voiceCallRate': 20},
  'service_area_selections': <Object>[],
  'host_profile_images': <Object>[],
  'user': {'id': id, 'documentId': user, 'name': name, 'role': 'Expert'},
};

/// `/expert-profiles` that matches every filter the app sends. Rows of
/// [listHidden] users (pending approval) only come back to the owner
/// lookup (sorted by `createdAt`), as the backend hides them from lists.
class _Backend implements HttpClientAdapter {
  final rows = [
    _row(11, 'h1', 'Host One'),
    _row(33, 'h3', 'Host Three', approved: false),
    _row(1, 'u1', 'Asha', approved: false),
  ];
  final listHidden = {'u1'};
  final queries = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    Object body = {'data': <Object>[]};
    if (o.path == '/api/expert-profiles') {
      final q = o.queryParameters;
      queries.add(q);
      final owner = q['sort[0]'] == 'createdAt:desc';
      bool hit(Map<String, Object?> r) {
        final user = r['user']! as Map;
        if (!owner && listHidden.contains(user['documentId'])) return false;
        final byUserDoc = q[r'filters[user][documentId][$eq]'];
        final byUserId = q[r'filters[user][id][$eq]'];
        final byDoc = q[r'filters[documentId][$eq]'];
        final byHandler = q[r'filters[handler][$eq]'];
        return (byUserDoc != null && user['documentId'] == byUserDoc) ||
            (byUserId != null && '${user['id']}' == '$byUserId') ||
            (byDoc != null && r['documentId'] == byDoc) ||
            (byHandler != null && r['handler'] == byHandler);
      }

      body = {'data': rows.where(hit).toList()};
    }
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

void main() {
  late _Backend backend;

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

  setUp(() async {
    rootBundle.clear();
    queryCache.clear();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
    await SessionStore.instance.signIn(
      user: {
        'id': 1,
        'documentId': 'u1',
        'name': 'Asha',
        'role': 'Expert',
        'mobile': '9999999999',
      },
      accessToken: 'access',
      expert: {'id': 101, 'documentId': 'exp-u1', 'handler': 'asha'},
    );
  });

  group('profile lookup', () {
    test('a host pending approval opens (no approval gate)', () async {
      final host = await ensureProfile(userDocumentId: 'h3', userId: '33');
      expect(host.userDocumentId, 'h3');
      expect(host.isApprovedHost, isFalse);
    });

    test('falls back to the numeric user id', () async {
      final host = await ensureProfile(userDocumentId: 'gone', userId: '11');
      expect(host.userDocumentId, 'h1');
      expect(
        backend.queries.map((q) => q[r'filters[user][id][$eq]']),
        contains('11'),
      );
    });

    test('your own pending profile opens through the owner lookup', () async {
      final host = await ensureProfile(userDocumentId: 'u1', userId: '1');
      expect(host.userDocumentId, 'u1');
      expect(host.name, 'ASHA');
      final byLink = await ensureHostByLink('asha');
      expect(byLink.userDocumentId, 'u1');
    });

    test('nothing found throws (the caller shows the alert)', () async {
      await expectLater(
        ensureProfile(userDocumentId: 'nobody'),
        throwsA(isA<ApiException>()),
      );
    });

    test('every profile link form resolves the real host', () async {
      for (final url in [
        'https://vibelive.angrymamba.com/host_three',
        'https://vibelive.angrymamba.com/expert-profile.php?userid=h3',
        'vibeexpoapp://vibelive.angrymamba.com/expert/host_three',
        'https://vibelive.angrymamba.com/expert-profile.php?userid=exp-h3',
      ]) {
        final id = LinkParser.parse(url)!.openUserId!;
        final host = await ensureHostByLink(id);
        expect(host.userDocumentId, 'h3', reason: url);
      }
      expect((await ensureHostByLink('33')).userDocumentId, 'h3');
    });
  });

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(const Size(390, 844));
    await tester.pumpWidget(
      CacheProvider(
        cache: queryCache,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          theme: AppTheme.dark(),
          locale: const Locale('en'),
          supportedLocales: AppI18n.supportedLocales,
          localizationsDelegates: [
            AppI18n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: home),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('nudge: the expert card opens the profile via expertDocId', (
    tester,
  ) async {
    await pumpApp(tester, const SizedBox());
    final data = ValueNotifier(
      const CallbackData(
        expertId: '11',
        expertDocId: 'exp-h1',
        name: 'Host One',
        voicePrice: 20,
        videoPrice: 30,
      ),
    );
    unawaited(showCallbackSheet(rootNavigatorKey.currentContext!, data));
    await settle(tester, 500);
    await tester.tap(find.text('Host One'));
    await settle(tester, 1500);
    expect(
      backend.queries.map((q) => q[r'filters[documentId][$eq]']),
      contains('exp-h1'),
    );
    expect(find.text('HOST ONE'), findsWidgets);
    expect(find.text('₹20/min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  });

  testWidgets('a profile deep link opens the host sheet', (tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final id = LinkParser.parse(
              'https://vibelive.angrymamba.com/host_one',
            )!.openUserId!;
            final host = await ensureHostByLink(id);
            if (context.mounted) await showHostProfile(context, host);
          },
          child: const Text('LINK'),
        ),
      ),
    );
    await tester.tap(find.text('LINK'));
    await settle(tester, 1200);
    expect(find.text('HOST ONE'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  });
}
