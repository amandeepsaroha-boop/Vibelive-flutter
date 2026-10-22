import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fquery/fquery.dart' show CacheProvider;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/homescreen/home_keys.dart';
import 'package:vibelive/app/api/homescreen/home_models.dart';
import 'package:vibelive/app/api/homescreen/home_queries.dart';
import 'package:vibelive/app/api/listingflow/filter_models.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';
import 'package:vibelive/app/listingflow/filter/filter_sheet.dart';
import 'package:vibelive/app/listingflow/search/search_header.dart';
import 'package:vibelive/app/listingflow/search/search_host_row.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_colors.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/core/utils/scale.dart';
import 'package:vibelive/main.dart';

/// Backend fixtures, as compact JSON.
final _fx =
    jsonDecode(r"""
{
  "asha": {"documentId": "exp1", "userDocumentId": "usr1", "name": "Asha Rao",
    "tagline": "Relationship coach for young couples",
    "categories": [{"name": "Dating"}], "languages": ["Hindi", "English"],
    "averageRating": 4.6, "reviewCount": 12, "isVerified": true,
    "rates": {"voiceCallRate": 12}, "durations": {"TotalMin": 1250}},
  "ashish": {"documentId": "exp2", "userDocumentId": "usr2",
    "name": "Ashish Kumar", "categories": ["Career"], "languages": ["Bengali"],
    "rates": {"voiceCallRate": 8.5}},
  "category": {"name": "Dating", "callsCount": 3},
  "categoryIn": {"category": {"name": "Dating"}, "location": {"name": "Delhi"}},
  "badges": {"data": [{"documentId": "exp1", "expert_verifications":
    [{"Verified_Badge": true, "insta_verified": true}]}]},
  "detail": {"data": [{"id": 1, "documentId": "exp1",
    "user": {"id": 10, "documentId": "usr1", "name": "Asha Rao"}}]},
  "languages": {"data": [{"id": 1, "name": "Hindi"},
    {"id": 2, "name": "LANG_MARATHI"}]},
  "form": {"data": {"questions": [{"key": "support_topic", "options": [
    {"value": "breakup", "label": "Breakup"},
    {"value": "dating", "label": "Dating"}]}]}},
  "feedHost": {"id": 5, "documentId": "exp5", "language": [{"name": "Punjabi"}],
    "service_area_selections": [{"snapshot": {
      "question": {"key": "support_topic"},
      "option": {"label": "Loneliness", "value": "lonely"}}}],
    "user": {"id": 50, "documentId": "usr5", "name": "Feed"}}
}
""")
        as Map<String, dynamic>;

/// `/search` answers after 300 ms ("asha" and "Dating" match), as does the
/// host-detail lookup; plus badges, languages and the support-topic form.
class _Backend implements HttpClientAdapter {
  final searches = <String>[];
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    final q = o.queryParameters;
    requests.add('${o.path} ${q.keys.join(',')}');
    if (o.path == '/api/search') searches.add('${q['q']}');
    if (o.path == '/api/search' || q.containsKey(r'filters[documentId][$eq]')) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return ResponseBody.fromString(
      jsonEncode(_reply(o.path, q)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object? _reply(String path, Map<String, dynamic> q) {
    switch (path) {
      case '/api/search':
        final text = '${q['q']}'.toLowerCase();
        final hits = text.contains('asha')
            ? [_fx['asha'], _fx['ashish']]
            : [if (text == 'dating') _fx['asha']];
        return {
          'results': {
            'experts': hits,
            'categories': [if (hits.isNotEmpty) _fx['category']],
            'category_and_location': [if (hits.isNotEmpty) _fx['categoryIn']],
          },
        };
      case '/api/expert-profiles':
        if (q.containsKey(r'filters[documentId][$in][0]')) return _fx['badges'];
        if (q[r'filters[documentId][$eq]'] == 'exp1') return _fx['detail'];
        return {'data': <Object>[]};
      case '/api/languages':
        return _fx['languages'];
      case '/api/interests/form':
        return _fx['form'];
      default:
        return {'data': <Object>[]};
    }
  }

  @override
  void close({bool force = false}) {}
}

/// An open filter sheet's outcome, filled when it closes.
class _Sheet {
  HostFilter? result;
  bool done = false;
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _rich(String text) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText() == text,
);

/// Chips past the edge of a horizontal strip are built but offstage.
Finder _chip(String text) => find.text(text, skipOffstage: false);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
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
        'email': 'a@b.co',
        'mobile': '9999999999',
      },
      accessToken: 'access',
    );
  });

  void phone(WidgetTester tester, [Size size = const Size(390, 844)]) {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(size);
  }

  Future<void> openSearch(
    WidgetTester tester, [
    Size size = const Size(390, 844),
  ]) async {
    phone(tester, size);
    await tester.pumpWidget(
      VibeLiveApp(
        themeController: ThemeController(ThemeMode.dark),
        localeController: LocaleController(const Locale('en')),
      ),
    );
    appRouter.go(AppRoutes.search);
    await _pump(tester, 400);
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await _pump(tester, 800); // 350 ms debounce + 300 ms backend
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  testWidgets('debounced search: skeleton, highlighted hits, badges', (
    tester,
  ) async {
    await openSearch(tester);
    expect(find.text('Search by name, category or location'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'asha');
    await _pump(tester, 200);
    expect(backend.searches, isEmpty); // still debouncing
    expect(find.byType(SearchHostRowSkeleton), findsWidgets);

    await _pump(tester, 250);
    expect(backend.searches, ['asha']);
    expect(find.byType(SearchHostRowSkeleton), findsWidgets);

    await _pump(tester, 500);
    expect(find.byType(SearchHostRowSkeleton), findsNothing);
    expect(find.text('EXPERTS'), findsOneWidget);
    expect(_rich('Asha Rao'), findsOneWidget);
    expect(_rich('Ashish Kumar'), findsOneWidget);
    expect(find.text('Dating in Delhi'), findsOneWidget);
    expect(find.text('3 calls'), findsOneWidget);
    expect(find.text('1.3K MIN CALLS HANDLED'), findsOneWidget);
    expect(find.text('4.6 (12)'), findsOneWidget);

    // The query is tinted inside the name.
    final name = tester.widget<RichText>(_rich('Asha Rao'));
    final spans = <TextSpan>[];
    name.text.visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    expect(spans.map((s) => s.text), ['Asha', ' Rao']);
    expect(spans.first.style?.color, BrandColors.lime);

    // Batched badge read upgraded Asha to an influencer (crown).
    expect(
      backend.requests.where((r) => r.contains(r'[$in][0]')),
      hasLength(1),
    );
    expect(find.byIcon(LucideIcons.crown), findsOneWidget);

    // A category row searches for its name at once.
    await _tap(tester, find.text('Dating').last);
    await _pump(tester, 400);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Dating',
    );
    expect(backend.searches.last, 'Dating');
    await finish(tester);
  });

  testWidgets('previous hits stay while typing; empty state; clear', (
    tester,
  ) async {
    await openSearch(tester);
    await search(tester, 'asha');
    expect(_rich('Asha Rao'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a&b');
    await _pump(tester, 450); // request in flight
    expect(backend.searches.last, 'a&b');
    expect(_rich('Asha Rao'), findsOneWidget);
    expect(find.byType(SearchHostRowSkeleton), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await _pump(tester, 400);
    expect(find.text('No results for “a&b”'), findsOneWidget);
    expect(_rich('Asha Rao'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Clear search'));
    await _pump(tester, 100);
    expect(find.text('Search by name, category or location'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a tapped hit spins, then opens the full profile', (
    tester,
  ) async {
    await openSearch(tester);
    await search(tester, 'asha');

    await tester.tap(_rich('Asha Rao'));
    await _pump(tester, 100);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      backend.requests.where((r) => r.contains(r'filters[documentId][$eq]')),
      hasLength(1),
    );

    await _pump(tester, 600);
    final header = tester.element(find.byType(SearchHeader));
    expect(ModalRoute.of(header)!.isCurrent, isFalse); // profile on top
    rootNavigatorKey.currentState!.pop();
    await _pump(tester, 600);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await finish(tester);
  });

  testWidgets('the filter sheet narrows the hits; chips remove filters', (
    tester,
  ) async {
    await openSearch(tester);
    await search(tester, 'asha');

    await tester.tap(find.bySemanticsLabel('Filters'));
    await _pump(tester, 600);
    expect(find.text('Filter Experts'), findsOneWidget);
    expect(_chip('Bengali'), findsOneWidget); // from the hits
    Finder inSheet(String text) => find.descendant(
      of: find.byType(FilterSheet),
      matching: _chip(text),
      skipOffstage: false,
    );
    expect(inSheet('English'), findsOneWidget);
    expect(inSheet('Career'), findsOneWidget); // a hit's category (search)

    await _tap(tester, _chip('Bengali'));
    await _pump(tester, 100);
    expect(find.text(' (1)'), findsOneWidget);
    await _tap(tester, find.text('Apply Filters'));
    await _pump(tester, 600);

    expect(find.text('Filter Experts'), findsNothing);
    expect(_rich('Ashish Kumar'), findsOneWidget);
    expect(_rich('Asha Rao'), findsNothing);
    expect(find.text('🌐 Bengali'), findsOneWidget);

    await tester.tap(find.text('🌐 Bengali'));
    await _pump(tester, 100);
    expect(_rich('Asha Rao'), findsOneWidget);
    expect(find.text('🌐 Bengali'), findsNothing);
    await finish(tester);
  });

  testWidgets('iPhone SE, keyboard open: field visible, hits scroll, drag '
      'dismisses', (tester) async {
    await openSearch(tester, const Size(375, 667));
    tester.view
      ..padding = const FakeViewPadding(top: 20 * 3)
      ..viewInsets = const FakeViewPadding(bottom: 300 * 3);
    await _pump(tester, 200);
    expect(tester.takeException(), isNull);
    final field = find.byType(TextField);
    expect(tester.getRect(field).top, greaterThanOrEqualTo(20));
    expect(tester.getRect(field).bottom, lessThan(667 - 300));
    expect(find.text('Search by name, category or location'), findsOneWidget);

    await search(tester, 'asha');
    expect(tester.takeException(), isNull);
    expect(_rich('Asha Rao'), findsOneWidget);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    // The list ends above the keyboard: its last row scrolls into the
    // visible area, and the drag dismisses the keyboard (RN on-drag).
    final last = find.text('Dating in Delhi');
    final results = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    await tester.scrollUntilVisible(last, 120, scrollable: results.last);
    await _pump(tester, 300);
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(667 - 300));
    expect(editable.focusNode.hasFocus, isFalse);
    await finish(tester);
  });

  group('showFilterSheet (Discover)', () {
    Future<_Sheet Function(HostFilter current)> host(
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      phone(tester);
      await tester.pumpWidget(
        CacheProvider(
          cache: queryCache,
          child: MaterialApp(
            theme: AppTheme.dark(),
            locale: const Locale('en'),
            supportedLocales: AppI18n.supportedLocales,
            localizationsDelegates: [AppI18n.delegate],
            home: Builder(
              builder: (context) {
                ctx = context;
                return const Scaffold();
              },
            ),
          ),
        ),
      );
      return (current) {
        final sheet = _Sheet();
        unawaited(
          showFilterSheet(ctx, current: current).then((r) {
            sheet
              ..result = r
              ..done = true;
          }),
        );
        return sheet;
      };
    }

    void seedFeed() {
      queryCache.setQueryData<FeedData, ApiException>(
        HomeKeys.feed,
        (_) => FeedData(
          pages: [
            HostPage(
              page: 1,
              hasMore: false,
              hosts: [HostCard.fromJson(_fx['feedHost'])],
            ),
          ],
          pageParams: [1],
        ),
      );
    }

    testWidgets('options from /languages, the form and the feed; Apply', (
      tester,
    ) async {
      seedFeed();
      final open = await host(tester);
      await _pump(tester, 300);

      final sheet = open(HostFilter.none);
      await _pump(tester, 600);
      expect(find.text('Filter Experts'), findsOneWidget);
      expect(_chip('Hindi'), findsOneWidget);
      expect(_chip('MARATHI'), findsOneWidget); // LANG_ prefix cleaned
      expect(_chip('Punjabi'), findsOneWidget); // feed host
      expect(_chip('Breakup'), findsOneWidget); // support topic
      expect(_chip('Loneliness'), findsOneWidget); // feed host topic

      await _tap(tester, _chip('Punjabi'));
      await _tap(tester, _chip('Hindi'));
      await _tap(tester, _chip('Breakup'));
      await _tap(tester, _chip('Loneliness')); // single: replaces
      await _pump(tester, 100);
      expect(find.text(' (2)'), findsOneWidget);
      expect(sheet.done, isFalse); // staged only

      await _tap(tester, find.text('Apply Filters'));
      await _pump(tester, 600);
      expect(sheet.done, isTrue);
      expect(
        sheet.result,
        const HostFilter(languages: ['Punjabi', 'Hindi'], topic: 'Loneliness'),
      );
      await finish(tester);
    });

    testWidgets('close = null; Clear All keeps it open and yields none', (
      tester,
    ) async {
      final open = await host(tester);
      await _pump(tester, 300);
      const current = HostFilter(languages: ['Hindi'], topic: 'Dating');

      final closed = open(current);
      await _pump(tester, 600);
      expect(find.text(' (1)'), findsOneWidget); // current is pre-staged
      await _tap(tester, _chip('Breakup'));
      await tester.tap(find.bySemanticsLabel('Close'));
      await _pump(tester, 600);
      expect(closed.done, isTrue);
      expect(closed.result, isNull);

      final cleared = open(current);
      await _pump(tester, 600);
      await _tap(tester, find.text('Clear All'));
      await _pump(tester, 300);
      expect(find.text('Filter Experts'), findsOneWidget); // still open
      expect(find.text('Clear All'), findsNothing);
      expect(cleared.done, isFalse);
      await tester.tap(find.bySemanticsLabel('Close'));
      await _pump(tester, 600);
      expect(cleared.done, isTrue);
      expect(cleared.result, HostFilter.none);
      await finish(tester);
    });
  });
}
