import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/splashscreen/startup_queries.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';

/// Answers everything at once, except the Discover feed's page 1, which
/// waits for [releaseFeed].
class _Backend implements HttpClientAdapter {
  final requests = <String>[];
  final _feed = Completer<void>();

  void releaseFeed() => _feed.complete();

  static bool _isFeed(RequestOptions o) =>
      o.path == '/api/expert-profiles' &&
      o.uri.queryParameters['popular'] == null &&
      o.uri.queryParameters['sort[0]'] == 'isActive:desc';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      _isFeed(options) ? 'FEED' : '${options.method} ${options.path}',
    );
    if (_isFeed(options)) await _feed.future;
    return ResponseBody.fromString(
      jsonEncode({
        'data': <Object>[],
        'meta': {
          'pagination': {'page': 1, 'pageSize': 16, 'pageCount': 0, 'total': 0},
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test(
    'startup: the feed goes first, the secondary reads wait for it',
    () async {
      queryCache.clear();
      final backend = _Backend();
      ApiClient.dio.httpClientAdapter = backend;
      await SessionStore.instance.signIn(
        user: {'id': 1, 'documentId': 'u1', 'name': 'Asha'},
        accessToken: 'access',
      );

      prefetchStartup();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Home's own reads only: the feed, popular, profile and wallet chip.
      expect(backend.requests.first, 'FEED');
      expect(backend.requests, contains('GET /api/wallets'));
      for (final later in [
        'GET /api/gst',
        'GET /api/pricing-config',
        'GET /api/page-contents',
        'GET /api/calls',
      ]) {
        expect(backend.requests, isNot(contains(later)));
      }

      backend.releaseFeed();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(backend.requests, containsAll(['GET /api/gst', 'GET /api/calls']));
      queryCache.clear();
    },
  );
}
