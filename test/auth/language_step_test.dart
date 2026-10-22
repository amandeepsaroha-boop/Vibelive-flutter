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
import 'package:vibelive/app/api/authscreen/auth_models.dart';
import 'package:vibelive/app/api/authscreen/interests_models.dart';
import 'package:vibelive/app/api/authscreen/languages_api.dart';
import 'package:vibelive/app/api/authscreen/onboarding_queries.dart';
import 'package:vibelive/app/authscreen/language_screen.dart';
import 'package:vibelive/app/component/c_loader.dart';
import 'package:vibelive/app/component/skeleton.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/api_exception.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

/// The admin form: its `expert_language` options are NOT what is offered.
const _form = {
  'app': {'id': 1, 'name': 'Vibe', 'key': 'vibe_os'},
  'questions': [
    {
      'key': 'expert_language',
      'title': 'Which languages should your expert speak?',
      'selectionMode': 'multi',
      'required': false,
      'minSelect': 1,
      'maxSelect': 2,
      'options': [
        {'value': 'English', 'label': 'English', 'isDefault': true},
        {'value': 'lang_hindi', 'label': 'Hindi'},
        {'value': 'lang_hinglish', 'label': 'Hinglish'},
      ],
    },
  ],
};

/// The Languages collection, as `/languages?sort=languageNames:asc` sends it.
const _rows = [
  {'id': 5, 'documentId': 'en-doc', 'languageNames': 'English'},
  {'id': 22, 'documentId': 'hi-doc', 'languageNames': 'हिंदी'},
  {'id': 20, 'documentId': 'ta-doc', 'languageNames': 'தமிழ்'},
];

Map<String, Object?> _page(List<Object> rows, {int page = 1, int count = 1}) =>
    {
      'data': rows,
      'meta': {
        'pagination': {'page': page, 'pageSize': 100, 'pageCount': count},
      },
    };

class _Backend implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Map<String, Object?> saved = {};
  int languagesStatus = 200;
  Object languages = _page(_rows);
  Duration delay = Duration.zero;

  RequestOptions only(String method, String path) =>
      requests.singleWhere((r) => r.method == method && r.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add(o);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final (int, Object) reply = switch ('${o.method} ${o.path}') {
      'GET /api/interests/form' => (200, _form),
      'GET /api/languages' => (languagesStatus, languages),
      'GET /api/me/interests' => (200, {'selections': saved}),
      'PUT /api/me/interests' => (200, {'savedCount': 1}),
      _ => (404, {'error': <String, Object>{}}),
    };
    return ResponseBody.fromString(
      jsonEncode(reply.$2),
      reply.$1,
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
    await QueryPersist.clearAll();
    for (final k in AppPrefs.keysWithPrefix('language_step_done:')) {
      await AppPrefs.remove(k);
    }
    ApiClient.dio.httpClientAdapter = backend = _Backend();
    await SessionStore.instance.signIn(
      user: {'id': 7, 'documentId': 'u1', 'date_of_birth': '1990-01-01'},
      accessToken: 'access',
    );
  });

  group('LanguagesApi', () {
    test('reads every page, A→Z by languageNames, 100 a page', () async {
      backend.languages = _page(_rows, count: 2);
      final first = await LanguagesApi.fetchAll();
      final pages = backend.requests.where((r) => r.path == '/api/languages');
      expect(pages, hasLength(2));
      for (final (i, r) in pages.indexed) {
        expect(r.queryParameters, {
          'sort': 'languageNames:asc',
          'pagination[page]': i + 1,
          'pagination[pageSize]': 100,
        });
      }
      // The same rows twice: first occurrence per id wins.
      expect([for (final l in first) l.label], ['English', 'हिंदी', 'தமிழ்']);
      expect(first.first.documentId, 'en-doc');
    });
  });

  group('LanguageStep.initialFromCatalog', () {
    final form = InterestForm.fromJson(_form).languageQuestion!;
    const langs = [
      InterestOption(value: 'en-doc', label: 'English'),
      InterestOption(value: 'hi-doc', label: 'हिंदी'),
      InterestOption(value: 'ta-doc', label: 'தமிழ்'),
    ];

    test('keeps saved languages, capped at the form max', () {
      expect(
        LanguageStep.initialFromCatalog(
          languages: langs,
          form: form,
          saved: ['ta-doc', 'gone', 'hi-doc', 'en-doc'],
        ),
        ['ta-doc', 'hi-doc'],
      );
    });

    test('an answer from the old form options maps by name', () {
      expect(
        LanguageStep.initialFromCatalog(
          languages: langs,
          form: form,
          saved: ['English', 'lang_hinglish'],
        ),
        ['en-doc'],
      );
    });

    test('nothing saved: the form default, matched by name', () {
      expect(LanguageStep.initialFromCatalog(languages: langs, form: form), [
        'en-doc',
      ]);
    });
  });

  group('the step offers the Languages collection', () {
    test(
      'choices are the collection; the form gives title and limits',
      () async {
        final data = await loadLanguageQuestion();
        final q = data.question!;
        expect(q.title, 'Which languages should your expert speak?');
        expect(q.maxSelect, 2);
        expect(
          [for (final o in q.options) o.value],
          ['en-doc', 'hi-doc', 'ta-doc'],
        );
        expect(
          [for (final o in q.options) o.label],
          ['English', 'हिंदी', 'தமிழ்'],
        );
        expect(data.selected, ['en-doc']);
      },
    );

    test('saves documentIds as the expert_language answer', () async {
      backend.saved = {
        'gender_pref': ['gender_pref_any'],
      };
      expect(await nextOnboardingStep(), OnboardingStep.language);
      expect(await saveLanguageStep(['en-doc', 'hi-doc']), isTrue);
      final put = backend.only('PUT', '/api/me/interests');
      expect((put.data as Map)['selections'], {
        'gender_pref': ['gender_pref_any'],
        'expert_language': ['en-doc', 'hi-doc'],
      });
      expect(await ensureLanguageStepStatus(), LanguageStepStatus.done);
    });

    test('a failed /languages throws, for the retry state', () async {
      backend.languagesStatus = 500;
      await expectLater(loadLanguageQuestion(), throwsA(isA<ApiException>()));
    });

    test('an empty collection: nothing to ask', () async {
      backend.languages = _page(const []);
      expect((await loadLanguageQuestion()).question, isNull);
    });
  });

  group('LanguageScreen', () {
    Future<void> open(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390, 844) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Scale.update(const Size(390, 844));
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const LanguageScreen()),
          GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        CacheProvider(
          cache: queryCache,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.dark(),
            locale: const Locale('en'),
            supportedLocales: AppI18n.supportedLocales,
            localizationsDelegates: [
              AppI18n.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 6));
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pump();
      await tester.tap(find.text(text));
      await _pump(tester, 300);
    }

    testWidgets('skeleton, collection chips, limit, save, then Home', (
      tester,
    ) async {
      backend.delay = const Duration(milliseconds: 200);
      await open(tester);
      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(CLoader), findsNothing);

      await _pump(tester, 1200);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.text('English'), findsOneWidget);
      expect(find.text('हिंदी'), findsOneWidget);
      expect(find.text('தமிழ்'), findsOneWidget);
      expect(find.text('Hinglish'), findsNothing, reason: 'form options');
      expect(find.textContaining('Pick up to 2.'), findsOneWidget);

      // English is pre-selected; a third pick is over the limit.
      await tapText(tester, 'हिंदी');
      await tapText(tester, 'தமிழ்');
      expect(find.text('You can pick up to 2.'), findsOneWidget);

      await tapText(tester, 'CONTINUE');
      await _pump(tester, 1500);
      final put = backend.only('PUT', '/api/me/interests');
      expect((put.data as Map)['selections'], {
        'expert_language': ['en-doc', 'hi-doc'],
      });
      expect(find.text('HOME'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      backend.languagesStatus = 400; // not retried by ApiClient
      await open(tester);
      await _pump(tester, 600);
      expect(
        find.text(
          'Could not load the languages. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      backend.languagesStatus = 200;
      await tapText(tester, 'TRY AGAIN');
      await _pump(tester, 600);
      expect(find.text('हिंदी'), findsOneWidget);
      await finish(tester);
    });
  });
}
