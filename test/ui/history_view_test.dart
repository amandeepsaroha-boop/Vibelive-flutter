import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fquery/fquery.dart' show CacheProvider;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:vibelive/app/api/callscreen/call_keys.dart';
import 'package:vibelive/app/api/callscreen/call_models.dart';
import 'package:vibelive/app/callscreen/history/helper/history_avatars.dart';
import 'package:vibelive/app/callscreen/history/history_row.dart';
import 'package:vibelive/app/callscreen/history/history_skeleton.dart';
import 'package:vibelive/app/callscreen/history/history_view.dart';
import 'package:vibelive/app/component/c_image.dart';
import 'package:vibelive/app/homescreen/helper/home_controller.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

const _me = {'id': 1, 'documentId': 'u1', 'name': 'Asha', 'role': 'Client'};

String _ago(Duration d) => DateTime.now().subtract(d).toUtc().toIso8601String();

Map<String, Object?> _party(int id, String doc, String name, String role) => {
  'id': id,
  'documentId': doc,
  'name': name,
  'role': role,
};

Map<String, Object?> _call(
  int id, {
  required Map<String, Object?>? caller,
  required Map<String, Object?>? receiver,
  required String status,
  required Duration? ago,
  String type = 'voiceCall',
  int? seconds = 0,
  Map<String, Object?> more = const {},
}) => {
  'id': id,
  'documentId': 'call$id',
  'callStatus': status,
  'type': type,
  'duration_sec': ?seconds,
  'startTime': ago == null ? null : _ago(ago),
  'caller': caller,
  'receiver': receiver,
  ...more,
};

/// An approved (or not) `/expert-profiles` row for a host user.
Map<String, Object?> _hostRow(
  int id,
  String doc,
  String name, {
  bool approved = true,
}) => {
  'id': id,
  'documentId': 'exp-$doc',
  'isApproved': approved,
  'isActive': true,
  'rates': {'videoCallRate': 30, 'voiceCallRate': 20},
  'host_profile_images': <Object>[],
  'user': {'id': id, 'documentId': doc, 'name': name, 'role': 'Expert'},
};

/// Page 1: a missed call from a client (nudge), a rated-able call to a host,
/// a declined call, then older calls; page 2: three more.
List<Map<String, Object?>> _page(int page) {
  if (page == 2) {
    return [
      for (var n = 11; n <= 13; n++)
        _call(
          100 + n,
          caller: _me,
          receiver: _party(n * 10, 'h$n', 'Host $n', 'Expert'),
          status: 'completed',
          ago: Duration(days: n),
          seconds: 60,
        ),
    ];
  }
  return [
    _call(
      101,
      caller: _me,
      receiver: _party(11, 'h1', 'Host One', 'Expert'),
      status: 'completed',
      ago: const Duration(hours: 2),
      seconds: 185,
    ),
    _call(
      102,
      caller: _party(22, 'c2', 'Client Two', 'Client'),
      receiver: _me,
      status: 'missed',
      type: 'videoCall',
      ago: const Duration(hours: 1),
    ),
    _call(
      103,
      caller: _me,
      receiver: _party(33, 'h3', 'Host Three', 'Expert'),
      status: 'declined',
      ago: const Duration(hours: 3),
    ),
    for (var n = 4; n <= 10; n++)
      _call(
        100 + n,
        caller: _me,
        receiver: _party(n * 10, 'h$n', 'Host $n', 'Expert'),
        status: 'completed',
        ago: Duration(days: n),
        seconds: 60 * n,
      ),
  ];
}

/// RN-sized category list: chips wrap over several rows.
const _moreCategories = [
  'Harassment or bullying',
  'Inappropriate content',
  'Fake profile',
  'Scam or fraud',
  'Other',
];

class _Backend implements HttpClientAdapter {
  _Backend({
    this.empty = false,
    this.failCalls = 0,
    this.rows,
    this.extra = const [],
    this.pingHours = 24,
    this.ping,
    this.reportFails = false,
  });

  final bool empty;

  /// Replaces page 1.
  final List<Map<String, Object?>>? rows;

  /// Listed first on page 1.
  final List<Map<String, Object?>> extra;

  /// App-config `expert_ping_config.validity_hours`.
  final Object? pingHours;

  /// `/call/ping-client` answer (default 200).
  final (int, Object)? ping;
  final bool reportFails;

  /// `/expert-profiles` rows by user documentId.
  final hosts = <String, Map<String, Object?>>{
    'h1': _hostRow(11, 'h1', 'Host One'),
    'h3': _hostRow(33, 'h3', 'Host Three', approved: false),
    'u1': _hostRow(1, 'u1', 'Asha', approved: false),
  };

  /// The first N `/calls` requests fail with a 400.
  int failCalls;
  final callPages = <int>[];
  final requests = <String>[];

  /// Query parameters of every `/expert-profiles` read.
  final profileQueries = <Map<String, dynamic>>[];
  final posts = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    if (o.method == 'POST') posts[o.path] = o.data;
    final (status, body) = await _reply(o);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Future<(int, Object)> _reply(RequestOptions o) async {
    if (o.path == '/api/calls') {
      final page = int.parse('${o.queryParameters['pagination[page]'] ?? 1}');
      callPages.add(page);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (failCalls-- > 0) {
        return (
          400,
          {
            'error': {'message': 'History is down'},
          },
        );
      }
      return (200, _calls(page));
    }
    if (o.path == '/api/expert-profiles') {
      profileQueries.add(o.queryParameters);
      final user = o.queryParameters[r'filters[user][documentId][$eq]'];
      final row = hosts[user];
      return (
        200,
        {
          'data': [?row],
        },
      );
    }
    if (o.path == '/api/call/ping-client') {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (ping != null) return ping!;
    }
    if (o.path == '/api/reports' && reportFails) {
      return (
        400,
        {
          'error': {'message': 'Reported user is required here'},
        },
      );
    }
    return (
      200,
      switch (o.path) {
        '/api/app-config' => {
          'data': {
            'expert_ping_config': {'validity_hours': pingHours},
          },
        },
        '/api/public-users/h1' => {
          'data': {
            ..._party(11, 'h1', 'Host One', 'Expert'),
            'expert': {'id': 5, 'documentId': 'exp1'},
          },
        },
        '/api/public-users/c9' => {
          'data': {
            ..._party(99, 'c9', 'Client Nine', 'Client'),
            'profilePic': {'url': 'https://cdn.test/c9.jpg'},
          },
        },
        '/api/report-categories' => {
          'data': [
            {'id': 1, 'documentId': 'rc1', 'category': 'Spam'},
            {'id': 2, 'documentId': 'rc2', 'category': 'Abuse'},
            for (final (i, name) in _moreCategories.indexed)
              {'id': 3 + i, 'documentId': 'rc${3 + i}', 'category': name},
          ],
        },
        '/api/reviews' when o.method == 'POST' => {
          'data': {'id': 900, 'rating': 4},
        },
        '/api/call/ping-client' => {'success': true},
        _ => {'data': <Object>[]},
      },
    );
  }

  Map<String, Object?> _calls(int page) => {
    'data': empty
        ? <Object>[]
        : page == 1
        ? [...extra, ...(rows ?? _page(1))]
        : _page(page),
    'meta': {
      'pagination': {'page': page, 'pageSize': 10, 'pageCount': empty ? 0 : 2},
    },
  };

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder, {int ms = 500}) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await _pump(tester, ms);
}

/// The ⋮ of the row showing [name].
Finder _menuOf(String name) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(HistoryRow)),
  matching: find.byIcon(LucideIcons.ellipsisVertical),
);

/// [matching] inside the row showing [name].
Finder _inRow(String name, Finder matching) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(HistoryRow)),
  matching: matching,
);

/// Closes the ⋮ menu (tap above it).
Future<void> _closeMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await _pump(tester, 400);
}

/// Raises the keyboard over 10 frames; returns how often each widget type
/// rebuilt meanwhile.
Future<Map<String, int>> _keyboardFrames(WidgetTester tester) async {
  final counts = <String, int>{};
  debugOnRebuildDirtyWidget = (e, _) {
    final n = e.widget.runtimeType.toString();
    counts[n] = (counts[n] ?? 0) + 1;
  };
  try {
    for (var k = 1; k <= 10; k++) {
      tester.view.viewInsets = FakeViewPadding(bottom: k * 90.0);
      await tester.pump(const Duration(milliseconds: 16));
    }
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}

/// What iOS reports while the keyboard is up: the keyboard as the bottom
/// view inset and no bottom padding (it covers the home indicator); the
/// status bar stays.
void _raiseKeyboard(WidgetTester tester, double keyboard, {double top = 0}) {
  tester.view
    ..viewInsets = FakeViewPadding(bottom: keyboard * 3)
    ..padding = FakeViewPadding(top: top * 3);
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
    HistoryAvatars.clear();
    await QueryPersist.clearAll();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
    await SessionStore.instance.signIn(
      user: {..._me, 'email': 'a@b.co', 'mobile': '9999999999'},
      accessToken: 'access',
    );
  });

  Future<HomeController> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Size size = const Size(390, 844),
    EdgeInsets safeArea = EdgeInsets.zero,
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
    final home = HomeController(HomeTab.history);
    await tester.pumpWidget(
      CacheProvider(
        cache: queryCache,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          theme: AppTheme.dark(),
          locale: locale,
          supportedLocales: AppI18n.supportedLocales,
          localizationsDelegates: [
            AppI18n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: SafeArea(child: HistoryView(home: home)),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return home;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  testWidgets('skeleton, then the log: outcome, duration, missed, nudge', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('LOGS'), findsOneWidget);
    expect(find.text('CALL HISTORY'), findsOneWidget);
    expect(find.byType(HistorySkeleton), findsOneWidget);

    await _pump(tester, 400);
    expect(find.byType(HistorySkeleton), findsNothing);
    expect(backend.callPages, [1]);
    expect(find.text('Client Two'), findsOneWidget);
    // Label on the name line + outcome line, like RN.
    expect(find.text('MISSED'), findsNWidgets(2));
    expect(find.text('NUDGE'), findsOneWidget); // incoming miss, < 24 h
    expect(find.text('Host One'), findsOneWidget);
    expect(find.text('3:05'), findsOneWidget);
    expect(find.text('DECLINED'), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.video), findsOneWidget); // the missed one
    expect(find.text('VOICE CALL'), findsWidgets);
    await finish(tester);
  });

  testWidgets('Hindi: header, labels and rows lay out cleanly', (tester) async {
    await open(tester, locale: const Locale('hi'));
    await _pump(tester, 400);
    expect(find.text('लॉग्स'), findsOneWidget);
    expect(find.text('याद दिलाएँ'), findsOneWidget); // NUDGE
    expect(find.text('Host One'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('page 1 renders instantly from the disk copy', (tester) async {
    final page = CallHistoryPage.fromResponse(
      backend._calls(1),
      page: 1,
      pageSize: 10,
    );
    QueryPersist.write(CallKeys.historyFirstPage('u1'), page.toJson());
    await open(tester);
    expect(find.byType(HistorySkeleton), findsNothing);
    expect(find.text('Host One'), findsOneWidget);
    await _pump(tester, 400); // network copy replaces it quietly
    expect(find.text('Host One'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('scrolling to the end loads page 2, then NO MORE CALLS', (
    tester,
  ) async {
    await open(tester);
    await _pump(tester, 400);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      3000,
    );
    await _pump(tester, 1500);
    expect(backend.callPages, [1, 2]);
    await tester.dragUntilVisible(
      find.text('NO MORE CALLS'),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.text('Host 13'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a failed page 1 offers a retry instead of the empty state', (
    tester,
  ) async {
    ApiClient.dio.httpClientAdapter = backend = _Backend(failCalls: 1);
    await open(tester);
    await _pump(tester, 400);
    expect(find.text("Couldn't load call history"), findsOneWidget);
    expect(find.text('History is down'), findsOneWidget);
    expect(find.text('No call history found'), findsNothing);

    await _tap(tester, find.text('RETRY'));
    expect(find.text('Host One'), findsOneWidget);
    expect(backend.callPages, [1, 1]);
    await finish(tester);
  });

  testWidgets('an empty log says so', (tester) async {
    ApiClient.dio.httpClientAdapter = backend = _Backend(empty: true);
    await open(tester);
    await _pump(tester, 400);
    expect(find.text('No call history found'), findsOneWidget);
    expect(find.text('NO MORE CALLS'), findsNothing);
    await finish(tester);
  });

  testWidgets('NUDGE pings the client who missed the call', (tester) async {
    await open(tester);
    await _pump(tester, 400);
    // A second tap while the first is in flight sends nothing.
    await tester.tap(find.text('NUDGE'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('NUDGE'), warnIfMissed: false);
    await _pump(tester, 500);
    expect(
      backend.requests.where((r) => r == 'POST /api/call/ping-client'),
      hasLength(1),
    );
    expect(backend.posts['/api/call/ping-client'], {'clientDocId': 'c2'});
    expect(find.text('Ping sent to Client Two'), findsOneWidget);
    await _tap(tester, find.text('OK'));
    await finish(tester);
  });

  testWidgets('rate a call: menu, stars, submit', (tester) async {
    await open(tester);
    await _pump(tester, 400);
    await _tap(tester, _menuOf('Host One'));
    expect(find.text('See Profile'), findsOneWidget);
    expect(find.text('Report this Host Profile'), findsOneWidget);
    expect(backend.requests, contains('GET /api/reviews')); // none left yet

    await _tap(tester, find.text('Rate this Call'));
    expect(find.text('with Host One'), findsOneWidget);
    expect(
      find.text('Select stars or write a comment to submit'),
      findsOneWidget,
    );
    await _tap(tester, find.byIcon(Icons.star_outline_rounded).at(3));
    expect(
      find.text('Select stars or write a comment to submit'),
      findsNothing,
    );

    await _tap(tester, find.text('SUBMIT REVIEW'), ms: 800);
    expect(backend.requests, contains('GET /api/public-users/h1'));
    expect(backend.posts['/api/reviews'], {
      'data': {
        'expert': 'exp1',
        'user': 'u1',
        'rating': 4,
        'comments': '',
        'call': 101, // numeric, like RN
      },
    });
    expect(find.text('Thanks!'), findsOneWidget);
    await _tap(tester, find.text('OK'));
    await finish(tester);
  });

  testWidgets('report a user: a category is required', (tester) async {
    await open(tester);
    await _pump(tester, 400);
    await _tap(tester, _menuOf('Client Two'));
    expect(find.text('Rate this Call'), findsNothing); // incoming call
    await _tap(tester, find.text('Report this User'));
    expect(find.text('Report Profile'), findsOneWidget);
    expect(find.text('Spam'), findsOneWidget);

    await _tap(tester, find.text('SUBMIT REPORT'));
    expect(find.text('Please select report category.'), findsOneWidget);
    await _tap(tester, find.text('OK'), ms: 700);

    await _tap(tester, find.text('Spam'));
    await tester.enterText(find.byType(TextField), 'Rude');
    await _tap(tester, find.text('SUBMIT REPORT'));
    expect(backend.posts['/api/reports'], {
      'data': {
        'reported_by_user': 'u1',
        'reported_to_user': 'c2',
        'report_category': 'rc1',
        'note': 'Rude',
        'report_status': 'new',
      },
    });
    expect(find.text('Report submitted.'), findsOneWidget);
    await _tap(tester, find.text('OK'));
    await finish(tester);
  });

  testWidgets('coming back to the tab refreshes page 1 quietly', (
    tester,
  ) async {
    final home = await open(tester);
    await _pump(tester, 400);
    expect(backend.callPages, [1]);

    home.select(HomeTab.discover);
    await _pump(tester, 100);
    expect(backend.callPages, [1]); // leaving does nothing
    home.select(HomeTab.history);
    await _pump(tester, 400);
    expect(backend.callPages, [1, 1]);
    expect(find.byType(HistorySkeleton), findsNothing);
    expect(find.text('Host One'), findsOneWidget);
    await finish(tester);
    home.dispose();
  });

  testWidgets('a client row that is no host opens nothing, silently', (
    tester,
  ) async {
    await open(tester);
    await _pump(tester, 400);
    await _tap(tester, find.text('Client Two'));
    expect(
      backend.requests.where((r) => r == 'GET /api/expert-profiles'),
      isNotEmpty,
    );
    expect(find.text('Something went wrong'), findsNothing);
    await finish(tester);
  });

  for (final (size, keyboard, safeArea) in const [
    (Size(375, 667), 300.0, EdgeInsets.only(top: 20)), // iPhone SE
    (Size(430, 932), 336.0, EdgeInsets.only(top: 59, bottom: 34)), // Pro Max
  ]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('review with the keyboard up on $label: comment and '
        'SUBMIT stay visible', (tester) async {
      await open(tester, size: size, safeArea: safeArea);
      await _pump(tester, 400);
      await _tap(tester, _menuOf('Host One'));
      await _tap(tester, find.text('Rate this Call'));
      await tester.enterText(find.byType(TextField), 'Great call ' * 30);
      _raiseKeyboard(tester, keyboard, top: safeArea.top);
      await _pump(tester, 400);

      expect(tester.takeException(), isNull); // no "bottom overflowed"
      final keyboardTop = size.height - keyboard;
      final submit = tester.getRect(find.text('SUBMIT REVIEW'));
      final field = tester.getRect(find.byType(TextField));
      expect(submit.bottom, lessThanOrEqualTo(keyboardTop));
      expect(tester.getRect(find.text('SKIP')).bottom, submit.bottom);
      expect(field.top, greaterThanOrEqualTo(safeArea.top));
      expect(field.top, lessThan(submit.top)); // the comment is on screen

      await tester.tap(find.text('SUBMIT REVIEW'));
      await _pump(tester, 800);
      expect(
        (backend.posts['/api/reviews'] as Map)['data'],
        containsPair('comments', 'Great call ' * 30),
      );
      // Close the success alert: an alert left open blocks the same one
      // in a later test (CAlert never stacks a duplicate).
      await _tap(tester, find.text('OK'));
      await finish(tester);
    });

    testWidgets('report with the keyboard up on $label: note and SUBMIT '
        'stay visible', (tester) async {
      await open(tester, size: size, safeArea: safeArea);
      await _pump(tester, 400);
      await _tap(tester, _menuOf('Client Two'));
      await _tap(tester, find.text('Report this User'));
      await _tap(tester, find.text('Other'));
      await tester.enterText(find.byType(TextField), 'Other: ${'x' * 400}');
      _raiseKeyboard(tester, keyboard, top: safeArea.top);
      await _pump(tester, 400);

      expect(tester.takeException(), isNull);
      final keyboardTop = size.height - keyboard;
      final submit = tester.getRect(find.text('SUBMIT REPORT'));
      final field = tester.getRect(find.byType(TextField));
      expect(submit.bottom, lessThanOrEqualTo(keyboardTop));
      expect(
        tester.getRect(find.text('Report Profile')).top,
        greaterThanOrEqualTo(safeArea.top),
      );
      expect(field.top, lessThan(submit.top));

      await tester.tap(find.text('SUBMIT REPORT'));
      await _pump(tester, 600);
      expect(
        (backend.posts['/api/reports'] as Map)['data'],
        containsPair('report_category', 'rc7'),
      );
      // Close the success alert: an alert left open blocks the same one
      // in a later test (CAlert never stacks a duplicate).
      await _tap(tester, find.text('OK'));
      await finish(tester);
    });
  }

  testWidgets('320 wide, Hindi: rows, menu and sheets lay out cleanly', (
    tester,
  ) async {
    await open(tester, locale: const Locale('hi'), size: const Size(320, 667));
    await _pump(tester, 400);
    expect(tester.takeException(), isNull);

    await _tap(tester, _menuOf('Host One'));
    expect(tester.takeException(), isNull);
    await _tap(tester, find.text('इस कॉल को रेटिंग दें').last);
    expect(find.text('Host One के साथ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a rising keyboard rebuilds only the review sheet inset', (
    tester,
  ) async {
    await open(tester, size: const Size(375, 667));
    await _pump(tester, 400);
    await _tap(tester, _menuOf('Host One'));
    await _tap(tester, find.text('Rate this Call'));
    await tester.enterText(find.byType(TextField), 'x');
    await _pump(tester, 100);
    final built = await _keyboardFrames(tester);
    expect(built['KeyboardInset'], greaterThan(0));
    for (final name in ['_ReviewSheet', 'HistoryView', 'HistoryRow']) {
      expect(built[name], isNull, reason: name);
    }
    await finish(tester);
  });

  testWidgets('a rising keyboard rebuilds only the report dialog inset', (
    tester,
  ) async {
    await open(tester, size: const Size(375, 667));
    await _pump(tester, 400);
    await _tap(tester, _menuOf('Client Two'));
    await _tap(tester, find.text('Report this User'));
    await tester.enterText(find.byType(TextField), 'x');
    await _pump(tester, 100);
    final built = await _keyboardFrames(tester);
    expect(built['KeyboardInset'], greaterThan(0));
    for (final name in ['_ReportDialog', '_Categories', 'HistoryView']) {
      expect(built[name], isNull, reason: name);
    }
    await finish(tester);
  });

  Future<void> signInAs(String role) => SessionStore.instance.signIn(
    user: {..._me, 'role': role, 'email': 'a@b.co', 'mobile': '9999999999'},
    accessToken: 'access',
  );

  group('host viewer', () {
    final client = _party(22, 'c2', 'Client Two', 'Client');
    final rows = [
      _call(
        201,
        caller: _party(44, 'c4', 'Old Miss', 'Client'),
        receiver: _me,
        status: 'missed',
        ago: const Duration(hours: 30),
      ),
      _call(
        202,
        caller: _party(55, 'c5', 'Declined Client', 'Client'),
        receiver: _me,
        status: 'declined',
        ago: const Duration(hours: 2),
      ),
      _call(
        203,
        caller: _me,
        receiver: _party(66, 'c6', 'Called Client', 'Client'),
        status: 'missed',
        ago: const Duration(hours: 1),
      ),
      _call(
        204,
        caller: _party(77, 'c7', 'Talked Client', 'Client'),
        receiver: _me,
        status: 'completed',
        ago: const Duration(hours: 1),
        seconds: 90,
      ),
      _call(
        205,
        caller: client,
        receiver: _me,
        status: 'missed',
        ago: const Duration(hours: 1),
      ),
    ];

    testWidgets('a client row: no profile, no call, no rate; NUDGE only on '
        'incoming misses / declines inside the window', (tester) async {
      await signInAs('Expert');
      ApiClient.dio.httpClientAdapter = backend = _Backend(rows: rows);
      await open(tester, size: const Size(390, 1200));
      await _pump(tester, 400);

      // Incoming missed (1 h) and declined (2 h): NUDGE.
      expect(_inRow('Client Two', find.text('NUDGE')), findsOneWidget);
      expect(_inRow('Declined Client', find.text('NUDGE')), findsOneWidget);
      // Outside 24 h, the viewer's own call, a connected call: none.
      expect(_inRow('Old Miss', find.text('NUDGE')), findsNothing);
      expect(_inRow('Called Client', find.text('NUDGE')), findsNothing);
      expect(_inRow('Talked Client', find.text('NUDGE')), findsNothing);
      expect(find.text('NUDGE'), findsNWidgets(2));

      // Tapping a client opens nothing and looks nothing up.
      await _tap(tester, find.text('Talked Client'));
      expect(backend.requests, isNot(contains('GET /api/expert-profiles')));
      expect(find.text('₹20/min'), findsNothing);

      await _tap(tester, _menuOf('Talked Client'));
      expect(find.text('See Profile'), findsNothing);
      expect(find.text('Rate this Call'), findsNothing);
      expect(find.text('Report this User'), findsOneWidget);
      await _closeMenu(tester);
      expect(backend.requests, isNot(contains('GET /api/expert-profiles')));
      await finish(tester);
    });

    testWidgets('validity_hours from app config widens the window', (
      tester,
    ) async {
      await signInAs('Expert');
      ApiClient.dio.httpClientAdapter = backend = _Backend(
        rows: rows,
        pingHours: 48,
      );
      await open(tester, size: const Size(390, 1200));
      await _pump(tester, 400);
      expect(_inRow('Old Miss', find.text('NUDGE')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a nudge shows the server copy (3 a day, cooldown) as RN', (
      tester,
    ) async {
      await signInAs('Expert');
      ApiClient.dio.httpClientAdapter = backend = _Backend(
        rows: rows,
        ping: (
          500,
          {
            'error': {'message': 'Please wait 10 minutes before pinging again'},
          },
        ),
      );
      await open(tester, size: const Size(390, 1200));
      await _pump(tester, 400);
      await _tap(tester, _inRow('Client Two', find.text('NUDGE')));
      expect(find.text('Error'), findsOneWidget);
      expect(
        find.text('Please wait 10 minutes before pinging again'),
        findsOneWidget,
      );
      await _tap(tester, find.text('OK'));
      await finish(tester);
    });

    testWidgets('a nudge over the daily limit shows the server message', (
      tester,
    ) async {
      await signInAs('Expert');
      ApiClient.dio.httpClientAdapter = backend = _Backend(
        rows: rows,
        ping: (429, {'message': 'You can ping a client only 3 times a day.'}),
      );
      await open(tester, size: const Size(390, 1200));
      await _pump(tester, 400);
      await _tap(tester, _inRow('Client Two', find.text('NUDGE')));
      expect(
        find.text('You can ping a client only 3 times a day.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('OK'));
      await finish(tester);
    });
  });

  group('client viewer', () {
    testWidgets('an approved host: tapping the row opens the profile with '
        'its call buttons', (tester) async {
      await open(tester);
      await _pump(tester, 400);
      await _tap(tester, find.text('Host One'), ms: 1200);
      expect(backend.requests, contains('GET /api/expert-profiles'));
      expect(find.text('HOST ONE'), findsWidgets);
      expect(find.text('₹20/min'), findsOneWidget); // voice
      expect(find.text('₹30/min'), findsOneWidget); // video
      await finish(tester);
    });

    testWidgets('a host that cannot be found says so', (tester) async {
      await open(tester);
      await _pump(tester, 400);
      await _tap(tester, find.text('Host 4'), ms: 1200);
      expect(find.text('Unable to open profile right now.'), findsOneWidget);
      await _tap(tester, find.text('OK'));
      await finish(tester);
    });

    testWidgets('See Profile in the menu opens the same profile', (
      tester,
    ) async {
      await open(tester);
      await _pump(tester, 400);
      await _tap(tester, _menuOf('Host One'));
      await _tap(tester, find.text('See Profile'), ms: 1200);
      expect(find.text('₹20/min'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a host pending approval, and your own pending profile, '
        'open', (tester) async {
      ApiClient.dio.httpClientAdapter = backend = _Backend(
        extra: [
          _call(
            301,
            caller: _me,
            receiver: _me,
            status: 'completed',
            ago: const Duration(minutes: 5),
            seconds: 10,
          ),
        ],
      );
      await open(tester);
      await _pump(tester, 400);
      // Your own row first: it is at the top of the list. It opens through
      // the owner lookup (Host Hub's read), which finds a pending profile.
      await _tap(tester, find.text('Asha'), ms: 1200);
      expect(find.text('ASHA'), findsWidgets);
      expect(
        backend.profileQueries.any(
          (q) =>
              q[r'filters[user][documentId][$eq]'] == 'u1' &&
              q['sort[0]'] == 'createdAt:desc',
        ),
        isTrue,
      );
      Navigator.of(rootNavigatorKey.currentContext!).pop();
      await _pump(tester, 800);
      await _tap(tester, find.text('Host Three'), ms: 1200);
      expect(find.text('HOST THREE'), findsWidgets);
      expect(find.text('₹20/min'), findsOneWidget);
      expect(find.text('Something went wrong'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('rate: caller + host + talk time + not missed, once', (
    tester,
  ) async {
    final host = _party(88, 'h8', 'Host Eight', 'Expert');
    ApiClient.dio.httpClientAdapter = backend = _Backend(
      rows: [
        _call(
          401,
          caller: _me,
          receiver: _party(11, 'h1', 'Host One', 'Expert'),
          status: 'completed',
          ago: const Duration(minutes: 1),
          seconds: 60,
        ),
        _call(
          402,
          caller: _me,
          receiver: _party(12, 'h2', 'Rated Host', 'Expert'),
          status: 'completed',
          ago: const Duration(minutes: 2),
          seconds: 60,
          more: {
            'review': {'id': 9, 'rating': 5},
          },
        ),
        _call(
          403,
          caller: host,
          receiver: _me,
          status: 'completed',
          ago: const Duration(minutes: 3),
          seconds: 60,
        ),
        _call(
          404,
          caller: _me,
          receiver: _party(14, 'h4', 'Missed Host', 'Expert'),
          status: 'missed',
          ago: const Duration(minutes: 4),
        ),
        _call(
          405,
          caller: _me,
          receiver: _party(15, 'h5', 'Zero Host', 'Expert'),
          status: 'completed',
          ago: const Duration(minutes: 5),
          seconds: 0,
        ),
      ],
    );
    await open(tester);
    await _pump(tester, 400);

    Future<void> menu(String name, {required String? rate}) async {
      await _tap(tester, _menuOf(name));
      for (final label in ['Rate this Call', 'Review Submitted']) {
        expect(find.text(label), label == rate ? findsOneWidget : findsNothing);
      }
      await _closeMenu(tester);
    }

    await menu('Host One', rate: 'Rate this Call');
    await menu('Rated Host', rate: 'Review Submitted');
    await menu('Host Eight', rate: null); // incoming: not the caller
    await menu('Missed Host', rate: null);
    await menu('Zero Host', rate: null); // no talk time
    await finish(tester);
  });

  testWidgets('rate: an unresolved host profile posts nothing', (tester) async {
    ApiClient.dio.httpClientAdapter = backend = _Backend(
      rows: [
        _call(
          501,
          caller: _me,
          receiver: _party(88, 'h8', 'Host Eight', 'Expert'),
          status: 'completed',
          ago: const Duration(minutes: 1),
          seconds: 60,
        ),
      ],
    );
    await open(tester);
    await _pump(tester, 400);
    await _tap(tester, _menuOf('Host Eight'));
    await _tap(tester, find.text('Rate this Call'));
    await _tap(tester, find.byIcon(Icons.star_outline_rounded).at(4));
    await _tap(tester, find.text('SUBMIT REVIEW'), ms: 800);
    expect(find.text('Unable to resolve Host Profile.'), findsOneWidget);
    expect(backend.posts.containsKey('/api/reviews'), isFalse);
    await _tap(tester, find.text('OK'));
    await finish(tester);
  });

  testWidgets('report a host: host label, the host as target', (tester) async {
    await open(tester);
    await _pump(tester, 400);
    await _tap(tester, _menuOf('Host One'));
    await _tap(tester, find.text('Report this Host Profile'));
    await _tap(tester, find.text('Abuse'));
    await _tap(tester, find.text('SUBMIT REPORT'));
    expect(backend.posts['/api/reports'], {
      'data': {
        'reported_by_user': 'u1',
        'reported_to_user': 'h1',
        'report_category': 'rc2',
        'note': '',
        'report_status': 'new',
      },
    });
    await _tap(tester, find.text('OK'));
    await finish(tester);
  });

  testWidgets('a deleted user: Unknown, reportable, failure copy as RN', (
    tester,
  ) async {
    ApiClient.dio.httpClientAdapter = backend = _Backend(
      reportFails: true,
      rows: [
        _call(
          601,
          caller: null,
          receiver: _me,
          status: 'completed',
          ago: null,
          seconds: null,
        ),
      ],
    );
    await open(tester);
    await _pump(tester, 400);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('N/A • NO DATE'), findsOneWidget);
    expect(find.text('NUDGE'), findsNothing);

    await _tap(tester, _menuOf('Unknown'));
    expect(find.text('See Profile'), findsOneWidget); // client viewer: RN
    await _tap(tester, find.text('Report this User'));
    await _tap(tester, find.text('Spam'));
    await _tap(tester, find.text('SUBMIT REPORT'));
    expect(backend.posts['/api/reports'], {
      'data': {
        'reported_by_user': 'u1',
        'report_category': 'rc1',
        'note': '',
        'report_status': 'new',
      },
    });
    expect(find.text('Failed to submit report.'), findsOneWidget);
    expect(find.text('Reported user is required here'), findsNothing);
    await _tap(tester, find.text('OK'));
    await finish(tester);
  });

  testWidgets('a user without a populated photo is looked up once', (
    tester,
  ) async {
    ApiClient.dio.httpClientAdapter = backend = _Backend(
      extra: [
        _call(
          701,
          caller: _party(99, 'c9', 'Client Nine', 'Client'),
          receiver: _me,
          status: 'completed',
          ago: const Duration(minutes: 1),
          seconds: 30,
        ),
      ],
    );
    await open(tester);
    await _pump(tester, 600);
    expect(
      backend.requests.where((r) => r == 'GET /api/public-users/c9'),
      hasLength(1),
    );
    final avatar = tester.widget<CAvatar>(
      _inRow('Client Nine', find.byType(CAvatar)),
    );
    expect(avatar.url, 'https://cdn.test/c9.jpg');
    await finish(tester);
  });

  testWidgets('every backend status: badge, label and outcome as RN', (
    tester,
  ) async {
    Map<String, Object?> row(
      int id,
      String name,
      String status, {
      bool outgoing = true,
      int? seconds = 0,
      Map<String, Object?> more = const {},
      String type = 'voiceCall',
    }) {
      final other = _party(id, 'p$id', name, 'Expert');
      return _call(
        id,
        caller: outgoing ? _me : other,
        receiver: outgoing ? other : _me,
        status: status,
        ago: Duration(minutes: id),
        seconds: seconds,
        more: more,
        type: type,
      );
    }

    ApiClient.dio.httpClientAdapter = backend = _Backend(
      rows: [
        row(1, 'S Completed', 'completed', seconds: 125),
        row(
          2,
          'S Minutes',
          'completed',
          outgoing: false,
          seconds: null,
          more: {'duration': 3},
          type: 'videoCall',
        ),
        row(3, 'S Missed In', 'missed', outgoing: false),
        row(4, 'S Missed Out', 'missed'),
        row(5, 'S Declined', 'declined'),
        row(6, 'S Cut', 'declined', outgoing: false, seconds: 40),
        row(7, 'S Busy', 'busy'),
        row(8, 'S Cancelled', 'cancelled'),
        row(9, 'S Ongoing', 'ongoing', outgoing: false),
        row(10, 'S Pending', 'pending'),
        row(11, 'S Forced', 'force complete by admin', seconds: 300),
        row(12, 'S NoDuration', 'completed', seconds: null),
      ],
    );
    await open(tester, size: const Size(390, 1800));
    await _pump(tester, 400);

    void expectRow(
      String name, {
      required IconData badge,
      required List<String> texts,
      List<String> absent = const [],
    }) {
      expect(_inRow(name, find.byIcon(badge)), findsOneWidget, reason: name);
      for (final t in texts) {
        expect(_inRow(name, find.text(t)), findsWidgets, reason: '$name $t');
      }
      for (final t in absent) {
        expect(_inRow(name, find.text(t)), findsNothing, reason: '$name $t');
      }
    }

    const up = LucideIcons.arrowUpRight;
    const down = LucideIcons.arrowDownLeft;
    expectRow('S Completed', badge: up, texts: ['2:05', 'VOICE CALL']);
    expectRow('S Minutes', badge: down, texts: ['3 mins', 'VIDEO CALL']);
    expect(_inRow('S Missed In', find.text('MISSED')), findsNWidgets(2));
    expectRow('S Missed In', badge: LucideIcons.phoneMissed, texts: []);
    // Outgoing miss: amber up-arrow, no MISSED label, "MISSED" outcome.
    expect(_inRow('S Missed Out', find.text('MISSED')), findsOneWidget);
    expectRow('S Missed Out', badge: up, texts: []);
    expect(_inRow('S Declined', find.text('DECLINED')), findsNWidgets(2));
    expectRow('S Declined', badge: LucideIcons.phoneOff, texts: []);
    // Declined after talk time reads as a miss.
    expectRow(
      'S Cut',
      badge: LucideIcons.phoneMissed,
      texts: ['MISSED', 'DECLINED'],
    );
    for (final name in ['S Busy', 'S Cancelled', 'S Pending']) {
      expectRow(name, badge: up, texts: ['VOICE CALL'], absent: ['MISSED']);
    }
    expectRow('S Ongoing', badge: down, texts: ['VOICE CALL']);
    expectRow('S Forced', badge: up, texts: ['5:00', 'VOICE CALL']);
    expectRow('S NoDuration', badge: up, texts: ['VOICE CALL']);
    expect(_inRow('S NoDuration', find.textContaining(':0')), findsNothing);
    await finish(tester);
  });

  group('row rules', () {
    CallHistoryItem item(String status, {bool outgoing = true, int sec = 0}) {
      final other = _party(9, 'p9', 'P', 'Expert');
      return CallHistoryItem(
        CallLog(
          _call(
            1,
            caller: outgoing ? _me : other,
            receiver: outgoing ? other : _me,
            status: status,
            ago: const Duration(hours: 1),
            seconds: sec,
          ),
        ),
        viewerDocumentId: 'u1',
        viewerRole: 'Client',
      );
    }

    test('direction for every status, both sides', () {
      final cases = {
        ('completed', true): CallDirection.outgoing,
        ('completed', false): CallDirection.incoming,
        ('missed', true): CallDirection.outgoingMissed,
        ('missed', false): CallDirection.missed,
        ('declined', true): CallDirection.declined,
        ('declined', false): CallDirection.declined,
        ('busy', true): CallDirection.outgoing,
        ('cancelled', false): CallDirection.incoming,
        ('ongoing', true): CallDirection.outgoing,
        ('pending', false): CallDirection.incoming,
        ('force complete by admin', true): CallDirection.outgoing,
      };
      for (final MapEntry(key: (status, out), :value) in cases.entries) {
        expect(item(status, outgoing: out).direction, value, reason: status);
      }
      expect(item('declined', sec: 5).direction, CallDirection.missed);
    });

    test('outcome: Missed / Declined, else the call type', () {
      expect(item('missed').outcome, CallOutcome.missed);
      expect(item('declined').outcome, CallOutcome.declined);
      expect(item('busy').outcome, CallOutcome.voiceCall);
    });

    test('ping window: RN Number(validity_hours || 24)', () {
      Duration w(Object? h) =>
          CallHistoryItem.pingWindow({'validity_hours': h});
      expect(CallHistoryItem.pingWindow(null), const Duration(hours: 24));
      expect(w(0), const Duration(hours: 24));
      expect(w(''), const Duration(hours: 24));
      expect(w('6'), const Duration(hours: 6));
      expect(w(0.5), const Duration(minutes: 30));
      expect(w('soon'), Duration.zero); // NaN: never
      expect(w(-3), Duration.zero);
      final missed = item('missed', outgoing: false);
      expect(missed.canPing(window: w('soon')), isFalse);
      expect(missed.canPing(window: w(2)), isTrue);
    });
  });
}
