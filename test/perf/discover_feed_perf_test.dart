import 'dart:async';
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
import 'package:vibelive/app/listingflow/widgets/host_grid_card.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/core/utils/scale.dart';
import 'package:vibelive/main.dart';
import 'package:vibelive/app/api/homescreen/feed_shuffle.dart';

import 'perf_harness.dart';

/// Feed pages of 6 regular hosts; page 2 is held until [releasePage2].
class _Backend implements HttpClientAdapter {
  _Backend({required this.total});

  /// `meta.pagination.total`.
  final int total;
  final feedPages = <int>[];
  final _page2 = Completer<void>();

  void releasePage2() => _page2.complete();

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final q = o.queryParameters;
    Object body = {'data': <Object>[]};
    if (o.path == '/api/expert-profiles' && q['popular'] != 'true') {
      final page = int.parse('${q['pagination[page]'] ?? 1}');
      feedPages.add(page);
      if (page == 2) await _page2.future;
      final first = (page - 1) * 6 + 1;
      final last = (page * 6).clamp(0, total);
      body = {
        'data': [for (var i = first; i <= last; i++) _host(i)],
        'meta': {
          'pagination': {
            'page': page,
            'pageCount': (total / 6).ceil(),
            'total': total,
          },
        },
      };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  static Map<String, Object?> _host(int id) => {
    'id': id,
    'documentId': 'exp$id',
    'tagline': 'Tagline $id',
    'user': {'id': id * 10, 'documentId': 'usr$id', 'name': 'Host $id'},
  };

  @override
  void close({bool force = false}) {}
}

/// Host names of the cards already on screen that rebuilt while [body] ran
/// (cards built for the first time don't count).
Future<Set<String>> rebuiltCards(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final before = find.byType(HostGridCard).evaluate().toSet();
  final names = <String>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final w = e.widget;
    if (w is HostGridCard && before.contains(e)) names.add(w.host.name);
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return names;
}

void main() {
  // These check paging and rendering in the server's order.
  FeedShuffle.enabled = false;
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
    await SessionStore.instance.signIn(
      user: {'id': 1, 'documentId': 'u1', 'name': 'Asha'},
      accessToken: 'access',
    );
  });

  /// Home on Discover with page 1 loaded (featured 1, pairs 2-3 and 4-5,
  /// and 6 alone in the last row).
  Future<void> openHome(WidgetTester tester, {required int total}) async {
    ApiClient.dio.httpClientAdapter = backend = _Backend(total: total);
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(const Size(390, 844)); // the app root does it on build
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.dark),
        localeController: LocaleController(const Locale('en')),
      ),
    );
    appRouter.go(AppRoutes.home);
    await pumpFrames(tester, 12, ms: 50);
    expect(find.byType(HostGridCardSkeleton), findsNothing);
  }

  /// Scrolls to the end: page 2 is asked for, and held.
  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -900),
    );
    await pumpFrames(tester, 30);
    await pumpFrames(tester, 20, ms: 50); // the overscroll stretch settles
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  testWidgets('load more: asked on the first scroll, the skeleton is the '
      'next cards, page 2 rebuilds only the row it completes', (tester) async {
    await openHome(tester, total: 12);
    expect(backend.feedPages, [1]); // nothing more until the user scrolls
    // Look-ahead: the first scroll asks for page 2, long before the end, and
    // starting it rebuilds no card — only 6's row swaps its empty slot for
    // the next card's skeleton.
    var rebuilt = await rebuiltCards(tester, () async {
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -300),
      );
      await pumpFrames(tester, 20, ms: 50);
    });
    expect(backend.feedPages, [1, 2]); // asked once
    // 6's row may first be built by this scroll; no other card rebuilds.
    expect(rebuilt.difference({'HOST 6'}), isEmpty);
    // Scrolling to the end while it is held asks nothing more and rebuilds
    // no card.
    rebuilt = await rebuiltCards(tester, () => scrollToEnd(tester));
    expect(backend.feedPages, [1, 2]);
    expect(rebuilt, isEmpty);
    // Card 7 fills 6's row, then a pair row (8, 9): three skeleton cards,
    // laid out exactly where those cards will be.
    expect(find.byType(HostGridCardSkeleton), findsNWidgets(3));
    final slot = tester.getRect(find.byType(HostGridCardSkeleton).first);
    final six = tester.getRect(
      find.ancestor(
        of: find.textContaining('HOST 6'),
        matching: find.byType(HostGridCard),
      ),
    );
    expect(slot.top, six.top);
    expect(slot.height, six.height);

    // Where the skeletons sit, relative to card 6 (scrolling may settle).
    final skeletonTops = [
      for (final e in find.byType(HostGridCardSkeleton).evaluate())
        tester.getRect(find.byWidget(e.widget)).top - six.top,
    ];
    rebuilt = await rebuiltCards(tester, () async {
      backend.releasePage2();
      await pumpFrames(tester, 10, ms: 50);
    });
    expect(find.byType(HostGridCardSkeleton), findsNothing);
    // The new cards sit where their skeletons were: no jump.
    double topOf(String name) =>
        tester
            .getRect(
              find.ancestor(
                of: find.textContaining(name),
                matching: find.byType(HostGridCard),
              ),
            )
            .top -
        tester
            .getRect(
              find.ancestor(
                of: find.textContaining('HOST 6'),
                matching: find.byType(HostGridCard),
              ),
            )
            .top;
    expect(topOf('HOST 7'), moreOrLessEquals(skeletonTops[0]));
    expect(topOf('HOST 8'), moreOrLessEquals(skeletonTops[1]));
    expect(topOf('HOST 9'), moreOrLessEquals(skeletonTops[2]));
    // Rows already on screen are untouched; 6's row is the one that changed.
    expect(rebuilt, {'HOST 6'});
    expect(backend.feedPages, [1, 2]);
    await finish(tester);
  });

  testWidgets('one card left: only the empty slot shows a skeleton', (
    tester,
  ) async {
    await openHome(tester, total: 7);
    await scrollToEnd(tester);
    expect(backend.feedPages, [1, 2]);
    expect(find.byType(HostGridCardSkeleton), findsOneWidget);
    backend.releasePage2();
    await pumpFrames(tester, 10, ms: 50);
    expect(find.byType(HostGridCardSkeleton), findsNothing);
    expect(find.textContaining('HOST 7'), findsOneWidget);
    await finish(tester);
  });
}
