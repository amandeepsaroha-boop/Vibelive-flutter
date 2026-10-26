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
import 'package:vibelive/app/authscreen/login_screen.dart';
import 'package:vibelive/app/client/personal_info/personal_info_screen.dart';
import 'package:vibelive/app/client/me/widgets/me_skeleton.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/app/navbar/bottombar/bottom_navbar.dart';
import 'package:vibelive/app/authscreen/helper/link_parser.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/theme_controller.dart';
import 'package:vibelive/main.dart';
import 'package:vibelive/app/hosthub/hub/hub_list.dart';

/// A client and a host, the host's stats and referral code; the expert's
/// vacation flag follows the last PUT.
class _Backend implements HttpClientAdapter {
  final requests = <String>[];
  bool vacation = false;

  /// Stats with every figure in the crores.
  bool big = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    return ResponseBody.fromString(
      jsonEncode(_reply(o)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object _reply(RequestOptions o) {
    if (o.method == 'PUT' && o.path == '/api/expert-profiles/exp1') {
      final data = (o.data as Map)['data'] as Map;
      vacation = data['vocationMode'] == true;
      return {'data': expert()};
    }
    return switch (o.path) {
      '/api/public-users/u-client' => {'data': client},
      '/api/public-users/u-ready' => {'data': readyClient},
      '/api/public-users/u-host' => {'data': hostUser()},
      '/api/expert-profiles/exp1' => {'data': expert()},
      '/api/user-statistics' when big => {
        'data': [
          {
            'id': 1,
            for (final k in const [
              'total_earnings',
              'total_incoming_calls',
              'total_profile_views',
              'total_referrals',
              'total_amount_withdrawal',
              'total_earnings_from_video_calls',
              'total_earnings_from_audio_calls',
              'total_earnings_from_referrals',
              'total_incoming_audio_calls',
              'total_incoming_video_minutes',
              'total_repeat_incoming_calls',
              'total_repeat_callers',
              'avg_incoming_call_minutes',
              'avg_outgoing_call_minutes',
            ])
              k: 987654321.75,
            'missed_call_percentage': 100,
            'average_rating': 4.95,
          },
        ],
      },
      '/api/user-statistics' => {
        'data': [
          {
            'id': 1,
            'total_earnings': 1500,
            'total_incoming_calls': 12,
            'total_profile_views': 1234,
            'average_rating': 4.5,
            'avg_incoming_call_minutes': 3.5,
          },
        ],
      },
      '/api/wallets' => {
        'data': [
          {'id': 1, 'balance': 120.5},
        ],
      },
      _ => {'data': <Object>[]},
    };
  }

  static const client = {
    'id': 1,
    'documentId': 'u-client',
    'name': 'Asha',
    'email': 'a@b.co',
    'mobile': '9999999999',
  };

  /// Personal Info complete: "Become a Host" is unlocked.
  static const readyClient = {
    'id': 3,
    'documentId': 'u-ready',
    'name': 'Meera',
    'email': 'm@b.co',
    'mobile': '9999999997',
    'address_JSON': {'state': 'Delhi', 'district': 'New Delhi'},
  };

  Map<String, Object?> expert() => {
    'id': 5,
    'documentId': 'exp1',
    'handler': 'riya',
    'isApproved': true,
    'isActive': true,
    'user_status': 'online',
    'vocationMode': vacation,
    'callAnyTime': !vacation,
    'schedule': <Object>[],
    'expert_verifications': <Object>[],
  };

  Map<String, Object?> hostUser() => {
    'id': 2,
    'documentId': 'u-host',
    'name': 'Riya',
    'email': 'r@b.co',
    'mobile': '9999999998',
    'user_referral': {'referralCode': 'vibe42'},
    'expert': expert(),
  };

  @override
  void close({bool force = false}) {}
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _meScrollable = find.descendant(
  of: find.byType(InfiniteScroll),
  matching: find.byType(Scrollable),
);

/// Scrolls [text] to the middle (clear of the floating navbar), then taps.
Future<void> _tap(WidgetTester tester, String text) async {
  final f = find.text(text);
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
  await tester.pump();
  await tester.tap(f);
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

  setUp(() {
    rootBundle.clear();
    queryCache.clear();
    ApiClient.dio.httpClientAdapter = backend = _Backend();
  });

  /// [size] is the phone in logical pixels; [bottomInset] its home
  /// indicator.
  Future<void> openMe(
    WidgetTester tester, {
    required Map<String, Object?> user,
    Map<String, Object?>? expert,
    ThemeMode theme = ThemeMode.dark,
    Size size = const Size(390, 844),
    Locale locale = const Locale('en'),
    double bottomInset = 0,
  }) async {
    await SessionStore.instance.signIn(
      user: {...user}..remove('expert'),
      expert: expert,
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
    appRouter.go('${AppRoutes.home}?tab=me');
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  testWidgets('client: skeleton, profile card and settings list', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.client);
    expect(find.byType(MeSkeleton), findsOneWidget);

    await _pump(tester, 600);
    expect(find.byType(MeSkeleton), findsNothing);
    expect(backend.requests, contains('GET /api/public-users/u-client'));
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('General User'), findsOneWidget);
    expect(find.text('MY WALLET'), findsOneWidget);
    expect(find.text('IDENTITY'), findsOneWidget);
    expect(find.text('Personal Info'), findsOneWidget);
    expect(find.text('Share Profile'), findsNothing); // hosts only
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('HOST HUB'), findsNothing);
    expect(find.text('RESOURCES'), findsOneWidget);

    // Personal Info incomplete: Become a Host explains what is missing.
    await _tap(tester, 'Become a Host');
    await _pump(tester, 300);
    expect(find.text('Complete Personal Info'), findsOneWidget);
    expect(find.textContaining('Missing: State, District'), findsOneWidget);
    await tester.tap(find.text('CANCEL'));
    await _pump(tester, 300);
    expect(find.text('Complete Personal Info'), findsNothing);

    // Rows open their screen.
    await _tap(tester, 'Personal Info');
    await _pump(tester, 600);
    expect(find.byType(PersonalInfoScreen), findsOneWidget);
    appRouter.pop();
    await _pump(tester, 600);
    expect(find.text('Asha'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('host: availability, dashboard figures and settings', (
    tester,
  ) async {
    await openMe(tester, user: backend.hostUser(), expert: backend.expert());
    await _pump(tester, 800);

    expect(find.text('Riya'), findsOneWidget);
    expect(find.text('@riya'), findsOneWidget);
    expect(find.text('Available for calls'), findsOneWidget);
    expect(find.text('AVAILABILITY MODES'), findsOneWidget);
    expect(find.text('₹1,500'), findsOneWidget); // lifetime earnings
    expect(find.text('VIBE42'), findsOneWidget); // invite card code

    // INVITE ALL opens the OS share sheet with the invite message.
    String? shared;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'share') {
        shared = (call.arguments as Map)['text'] as String?;
      }
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
    await _tap(tester, 'INVITE ALL');
    await _pump(tester, 300);
    expect(shared, contains('Use my code VIBE42'));
    expect(shared, contains('/VIBE42?r=i')); // link not HTML-escaped
    expect(backend.requests, contains('GET /api/referral/VIBE42/copy'));
    // Tiles are built lazily: scroll down to them, then back up.
    for (final value in ['1,234', '3m 30s']) {
      // profile views, avg incoming duration
      await tester.scrollUntilVisible(
        find.text(value),
        300,
        scrollable: _meScrollable,
      );
    }
    expect(find.text('AVG DURATION (IN)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Vacation'),
      -300,
      scrollable: _meScrollable,
    );
    await _pump(tester, 100);

    // Vacation: saved, re-read into the session, shown on the card.
    await tester.tap(find.text('Vacation'));
    await tester.pump();
    expect(find.text('Updating...'), findsOneWidget);
    await _pump(tester, 800);
    expect(backend.requests, contains('PUT /api/expert-profiles/exp1'));
    expect(backend.vacation, isTrue);
    expect(find.text("Calls are paused while you're away."), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('On vacation'), // the profile card's pill
      -300,
      scrollable: _meScrollable,
    );
    expect(find.text('Available for calls'), findsNothing);

    // Settings: Host Hub with the badge prompt (approved, not applied).
    await tester.tap(find.text('Settings'));
    await _pump(tester, 400);
    expect(find.text('INSIGHTS'), findsNothing);
    expect(find.text('Share Profile'), findsOneWidget);
    expect(find.text('Become a Host'), findsNothing); // clients only
    await Scrollable.ensureVisible(
      tester.element(find.text('HOST HUB')),
      alignment: 0.3,
    );
    await _pump(tester, 100);
    expect(find.text('✨ APPLY FOR BADGE'), findsNWidgets(2));
    expect(find.text('Verification Badge'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a complete profile celebrates Become a Host once', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.readyClient, theme: ThemeMode.light);
    await _pump(tester, 800);
    expect(find.text('🎉 Profile complete!'), findsOneWidget);
    expect(find.text('🎁 WANT TO BECOME A HOST?'), findsOneWidget);

    await Scrollable.ensureVisible(
      tester.element(find.text('🎉 Profile complete!')),
      alignment: 0.4,
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Dismiss'));
    await _pump(tester, 200);
    expect(find.text('🎉 Profile complete!'), findsNothing);
    expect(
      AppPrefs.getString('@has_seen_become_host_unlock_1:u-ready'),
      'true',
    );
    await finish(tester);
  });

  testWidgets('menu: options for a client, logout returns to login', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.client);
    await _pump(tester, 600);

    await tester.tap(find.bySemanticsLabel('More'));
    await _pump(tester, 400);
    expect(find.text('OPTIONS'), findsOneWidget);
    expect(find.text('Become a Host'), findsWidgets);
    expect(find.text('View Public Profile'), findsNothing); // hosts only

    await tester.tap(find.text('Logout Session'));
    await _pump(tester, 1500);
    expect(SessionStore.instance.value.isAuthenticated, isFalse);
    expect(backend.requests, contains('POST /api/session-auth/logout'));
    expect(find.byType(LoginScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('host menu: Share Profile (RN link), no extra options', (
    tester,
  ) async {
    await openMe(tester, user: backend.hostUser(), expert: backend.expert());
    await _pump(tester, 800);

    String? shared;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'share') {
        shared = (call.arguments as Map)['text'] as String?;
      }
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));

    await tester.tap(find.bySemanticsLabel('More'));
    await _pump(tester, 400);
    final sheet = find.ancestor(
      of: find.text('OPTIONS'),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: sheet.first, matching: find.text('Share Profile')),
      findsOneWidget,
    );
    expect(find.text('View Public Profile'), findsNothing);
    expect(find.text('Logout Session'), findsOneWidget);

    await tester.tap(
      find.descendant(of: sheet.first, matching: find.text('Share Profile')),
    );
    await _pump(tester, 600);
    expect(
      shared,
      'Check out my profile on Vibe: ${LinkParser.shareLink('riya')}',
    );
    await finish(tester);
  });

  testWidgets('the end of the list clears the navbar and home indicator', (
    tester,
  ) async {
    await openMe(tester, user: _Backend.client, bottomInset: 34);
    await _pump(tester, 600);
    final navTop = tester.getRect(find.byType(BottomNavbar)).top;

    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 1200);
    final resources = find.ancestor(
      of: find.text('RESOURCES'),
      matching: find.byType(HubListCard),
    );
    expect(tester.getRect(resources.first).bottom, lessThan(navTop));
    await finish(tester);
  });

  testWidgets('320 wide, Hindi host with big numbers: no overflow', (
    tester,
  ) async {
    backend.big = true;
    await openMe(
      tester,
      user: {
        ...backend.hostUser(),
        'name': 'Venkata Lakshmi Narasimha Subrahmanyam Chakravarthy',
      },
      expert: backend.expert(),
      size: const Size(320, 667),
      locale: const Locale('hi'),
      theme: ThemeMode.light,
    );
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);

    // Every dashboard tile, then the settings list.
    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);
    await tester.fling(_meScrollable, const Offset(0, 3000), 3000);
    await _pump(tester, 800);
    await tester.tap(find.text('सेटिंग्स'));
    await _pump(tester, 400);
    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('और विकल्प'));
    await _pump(tester, 400);
    expect(find.text('विकल्प'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('320 wide, Hindi client with the host celebration: no overflow', (
    tester,
  ) async {
    await openMe(
      tester,
      user: _Backend.readyClient,
      size: const Size(320, 667),
      locale: const Locale('hi'),
    );
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);
    await tester.fling(_meScrollable, const Offset(0, -3000), 3000);
    await _pump(tester, 800);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
