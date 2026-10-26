import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:vibelive/app/component/skeleton.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/razorpay_gateway.dart';
import 'package:vibelive/app/paymentscreen/wallet/wallet_screen.dart';
import 'package:vibelive/app/paymentscreen/wallet/widgets/transaction_list.dart';
import 'package:vibelive/core/i18n/i18n.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/query/query_client.dart';
import 'package:vibelive/core/query/query_persist.dart';
import 'package:vibelive/core/router/app_router.dart';
import 'package:vibelive/core/session/session_store.dart';
import 'package:vibelive/core/storage/app_prefs.dart';
import 'package:vibelive/core/theme/app_colors.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

Map<String, Object?> _me({String? mobile = '9999999999'}) => {
  'id': 1,
  'documentId': 'u1',
  'name': 'Asha',
  'email': 'a@b.co',
  'mobile': mobile,
};

/// Row [i]: odd rows are gateway top-ups, even rows paid video calls.
Map<String, Object?> _tx(int i) => i.isOdd
    ? {
        'id': i,
        'transaction_Id': 'RZP_$i',
        'amount': 100,
        'paymentStatus': 'success',
        'transactionType': 'topup',
        'method': 'razorpay',
        'createdAt': '2026-10-01T10:00:00.000Z',
        'to_wallet': {'wallet_type': 'CASH_WALLET'},
      }
    : {
        'id': i,
        'transaction_Id': 'TX_$i',
        'amount': 20,
        'paymentStatus': 'pending',
        'transactionType': 'call',
        'createdAt': '2026-10-01T10:00:00.000Z',
        'FromWallet': {'wallet_type': 'CASH_WALLET'},
        'call': {
          'type': 'videocall',
          'caller': {'name': 'Asha'},
          'receiver': {'name': 'Meera'},
        },
        'metadata': {'amountWithGST': 23.6},
      };

class _Backend implements HttpClientAdapter {
  double cash = 1000;
  double earnings = 118;
  String? mobile = '9999999999';
  int totalTx = 13;
  Duration delay = Duration.zero;
  Object verifyReply = {
    'data': {'status': 'success'},
  };
  int verifyCode = 200;
  int transferCode = 200;
  final requests = <String>[];
  final pages = <int>[];
  final posted = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async {
    requests.add('${o.method} ${o.path}');
    if (o.method == 'POST') posted[o.path] = o.data;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final code = switch (o.path) {
      '/api/razorpay/payments/verify' => verifyCode,
      '/api/wallet-transfer/earnings-to-cash' => transferCode,
      _ => 200,
    };
    return ResponseBody.fromString(
      jsonEncode(_reply(o)),
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  Object _reply(RequestOptions o) {
    final q = o.queryParameters;
    switch ('${o.method} ${o.path}') {
      case 'GET /api/public-users/u1':
        return {'data': _me(mobile: mobile)};
      case 'GET /api/wallets':
        return {
          'data': [
            {'id': 1, 'wallet_type': 'CASH_WALLET', 'balance': cash},
            {'id': 2, 'wallet_type': 'EARNINGS_WALLET', 'balance': earnings},
          ],
        };
      case 'GET /api/transactions':
        final page = int.parse('${q['pagination[page]']}');
        pages.add(page);
        final from = (page - 1) * 10 + 1;
        final to = (page * 10).clamp(0, totalTx);
        return {
          'data': [for (var i = from; i <= to; i++) _tx(i)],
        };
      case 'GET /api/gst':
        return {
          'data': {'IGST': 18},
        };
      case 'GET /api/payment-gateway/selection':
        return {
          'data': {'paymentGateway': 'razorpay'},
        };
      case 'POST /api/razorpay/wallet-recharge/initiate':
        return {
          'data': {
            'orderId': 'order_1',
            'keyId': 'rzp_test_key',
            'amount': 59000,
            'currency': 'INR',
            'transactionId': 'RZP_TXN_1',
          },
        };
      case 'POST /api/razorpay/payments/verify':
        return verifyReply;
      case 'POST /api/wallet-transfer/earnings-to-cash':
        return transferCode == 200
            ? {'status': 'success'}
            : {
                'error': {'message': 'Transfer limit reached'},
              };
      default:
        return {'data': <Object>[]};
    }
  }

  @override
  void close({bool force = false}) {}
}

class _FakeCheckout implements RazorpayGateway {
  CheckoutOutcome next = const CheckoutPaid(
    paymentId: 'pay_1',
    orderId: 'order_1',
    signature: 'sig_1',
  );
  final opened = <Map<String, dynamic>>[];

  @override
  Future<CheckoutOutcome> open(Map<String, dynamic> options) async {
    opened.add(options);
    return next;
  }
}

Future<void> _pump(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
}

final _shot = GlobalKey();

/// Real fonts for the screenshots (the test font draws boxes).
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  const sdk = '/Users/devloper/Dev/flutter/bin/cache/artifacts/material_fonts';
  final home = Platform.environment['HOME'];
  await load('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold', 'Black'])
      '$sdk/Roboto-$w.ttf',
  ]);
  await load('MaterialIcons', ['$sdk/MaterialIcons-Regular.otf']);
  await load('packages/lucide_icons_flutter/Lucide', [
    '$home/.pub-cache/hosted/pub.dev/lucide_icons_flutter-4.0.0/assets/lucide.ttf',
  ]);
}

Future<void> _save(WidgetTester tester, String dir, String name) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  late _Backend backend;
  late _FakeCheckout checkout;

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
    ApiClient.dio.httpClientAdapter = backend = _Backend();
    RazorpayGateway.instance = checkout = _FakeCheckout();
    await SessionStore.instance.signIn(user: _me(), accessToken: 'access');
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool dark = true,
    bool settle = true,
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Scale.update(size);
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: AppRoutes.wallet,
      routes: [
        GoRoute(
          path: AppRoutes.wallet,
          builder: (_, _) => const WalletScreen(),
        ),
        for (final (path, label) in const [
          (AppRoutes.home, 'HOME PAGE'),
          (AppRoutes.personalInfo, 'PERSONAL INFO PAGE'),
        ])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text(label)),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _shot,
        child: CacheProvider(
          cache: queryCache,
          child: MaterialApp.router(
            routerConfig: router,
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: scaffoldMessengerKey,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            locale: const Locale('en'),
            supportedLocales: AppI18n.supportedLocales,
            localizationsDelegates: [
              AppI18n.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
          ),
        ),
      ),
    );
    if (settle) await _pump(tester, 600);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 6));
  }

  /// Add Money → ₹500 preset → ADD MONEY.
  Future<void> startTopUp(WidgetTester tester) async {
    await tester.tap(find.text('Add money'));
    await _pump(tester, 400);
    expect(find.text('Add Money'), findsOneWidget);
    await tester.tap(find.text('₹500').first);
    await _pump(tester, 100);
    await _tap(tester, find.text('ADD MONEY'));
    await _pump(tester, 600);
  }

  testWidgets('skeleton first, then balances and history', (tester) async {
    backend.delay = const Duration(milliseconds: 300);
    await open(tester, settle: false);
    await _pump(tester, 100);
    expect(find.byType(TransactionListSkeleton), findsOneWidget);
    expect(find.byType(Shimmer), findsWidgets);
    expect(find.text('₹1,118.0'), findsNothing);

    await _pump(tester, 800);
    expect(find.byType(TransactionListSkeleton), findsNothing);
    expect(find.text('₹1,118.0'), findsOneWidget);
    expect(find.text('₹1,000.0'), findsOneWidget);
    expect(find.text('₹118.0'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget); // the split
    // Row 1: a top-up with its invoice; row 2: a paid video call.
    expect(find.text('Wallet Top Up'), findsWidgets);
    expect(find.text('+₹100.00'), findsWidgets);
    expect(find.text('Paid to Vibe Live'), findsWidgets);
    expect(find.text('Video Call to Meera'), findsWidgets);
    expect(find.text('-₹23.60'), findsWidgets);
    expect(find.text('PENDING'), findsWidgets);
    expect(find.text('Invoice'), findsWidgets);
    await finish(tester);
  });

  testWidgets('pages the history, then shows the end', (tester) async {
    await open(tester);
    expect(backend.pages, [1]);
    expect(find.text('NO MORE TRANSACTIONS'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('NO MORE TRANSACTIONS'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await _pump(tester, 200);
    expect(backend.pages, [1, 2]);
    expect(find.text('RZP_13'), findsOneWidget);
    expect(find.text('NO MORE TRANSACTIONS'), findsOneWidget);

    // A tab reloads page 1 with its own filter.
    await tester.tap(find.text('EARNINGS').last);
    await _pump(tester, 300);
    expect(backend.pages, [1, 2, 1]);
    await finish(tester);
  });

  testWidgets('top-up success: backend order, checkout, verify', (
    tester,
  ) async {
    await open(tester);
    await startTopUp(tester);

    expect(backend.posted['/api/razorpay/wallet-recharge/initiate'], {
      'amount': 500.0,
    });
    final options = checkout.opened.single;
    expect(options['order_id'], 'order_1');
    expect(options['key'], 'rzp_test_key');
    expect(options['amount'], 59000);
    expect(options.toString(), isNot(contains('ecret')));
    expect(backend.posted['/api/razorpay/payments/verify'], {
      'razorpay_payment_id': 'pay_1',
      'razorpay_order_id': 'order_1',
      'razorpay_signature': 'sig_1',
    });
    expect(find.text('Payment Successful'), findsOneWidget);
    expect(find.text('Your wallet has been updated.'), findsOneWidget);
    expect(backend.requests, contains('POST /api/razorpay/success'));

    final walletReads = backend.requests
        .where((r) => r == 'GET /api/wallets')
        .length;
    expect(walletReads, greaterThanOrEqualTo(2)); // refreshed after paying
    await tester.tap(find.text('CONTINUE'));
    await _pump(tester, 300);
    expect(find.text('Payment Successful'), findsNothing);
    await finish(tester);
  });

  testWidgets('top-up failure shows the gateway reason and reports it', (
    tester,
  ) async {
    checkout.next = const CheckoutFailed(code: 0, description: 'Card declined');
    await open(tester);
    await startTopUp(tester);

    expect(find.text('Payment Failed'), findsOneWidget);
    expect(find.text('Card declined'), findsOneWidget);
    expect(backend.requests, contains('POST /api/razorpay/failure'));
    expect(
      backend.requests,
      isNot(contains('POST /api/razorpay/payments/verify')),
    );
    await finish(tester);
  });

  testWidgets('a rejected verification is a failure', (tester) async {
    backend.verifyReply = {
      'data': {'status': 'failed'},
    };
    await open(tester);
    await startTopUp(tester);
    expect(find.text('Payment Failed'), findsOneWidget);
    expect(
      find.text('Payment verification could not be completed.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a dropped verification ends pending, never failed', (
    tester,
  ) async {
    backend.verifyCode = 500;
    await open(tester);
    await startTopUp(tester);
    expect(find.text('Verifying Payment...'), findsOneWidget);

    await _pump(tester, 11000); // 4 status polls, 2.5 s apart
    expect(
      backend.requests
          .where((r) => r == 'GET /api/razorpay/payments/RZP_TXN_1/status')
          .length,
      4,
    );
    expect(find.text('Verifying Payment...'), findsNothing);
    expect(find.text('Payment Received'), findsOneWidget);
    expect(find.text('Payment Failed'), findsNothing);
    await finish(tester);
  });

  testWidgets('closing the checkout shows nothing', (tester) async {
    checkout.next = const CheckoutCancelled();
    await open(tester);
    await startTopUp(tester);

    expect(checkout.opened, hasLength(1));
    expect(find.text('Payment Failed'), findsNothing);
    expect(find.text('Payment Successful'), findsNothing);
    expect(find.text('Add Money'), findsNothing);
    expect(backend.requests, isNot(contains('POST /api/razorpay/failure')));
    await finish(tester);
  });

  testWidgets('incomplete profile: alert, then Personal Info', (tester) async {
    backend.mobile = null;
    await SessionStore.instance.signIn(
      user: _me(mobile: null),
      accessToken: 'access',
    );
    await open(tester);
    await tester.tap(find.text('Add money'));
    await _pump(tester, 400);
    expect(find.text('Profile Incomplete'), findsOneWidget);
    expect(find.text('Add Money'), findsNothing);

    await tester.tap(find.text('UPDATE PROFILE'));
    await _pump(tester, 600);
    expect(find.text('PERSONAL INFO PAGE'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('add money: cards only, pinned button once one is picked', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Add money'));
    await _pump(tester, 400);
    // No manual amount box; the button waits for a card.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('ADD MONEY'), findsNothing);

    await tester.tap(find.text('₹1,000').first);
    await _pump(tester, 300);
    expect(find.text('ADD MONEY'), findsOneWidget);
    expect(find.text('₹180.00'), findsOneWidget);
    expect(find.text('₹1180.00'), findsOneWidget);
    expect(find.text('₹1000.00 will be added to your wallet'), findsOneWidget);

    // Tapping it again clears the pick: the button goes away.
    await tester.tap(find.text('₹1,000').first);
    await _pump(tester, 300);
    expect(find.text('ADD MONEY'), findsNothing);
    await finish(tester);
  });

  testWidgets('transfer: presets, GST total, minimum and confirm', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.bySemanticsLabel('Transfer earnings to cash'));
    await _pump(tester, 500);
    expect(find.text('Earnings → Cash'), findsOneWidget);
    // 118 earnings at 18% GST: at most 100 can move.
    expect(find.text('MAX: ₹100.0'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));

    await tester.tap(find.text('50%'));
    await _pump(tester, 100);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('+ ₹50.0'), findsOneWidget);
    expect(find.text('₹9.0'), findsOneWidget);
    expect(find.text('- ₹59.0'), findsOneWidget);

    await _tap(tester, find.text('CONFIRM TRANSFER'));
    await _pump(tester, 600);
    expect(backend.posted['/api/wallet-transfer/earnings-to-cash'], {
      'amount': 50.0,
    });
    expect(find.text('Transfer completed successfully!'), findsOneWidget);
    expect(find.text('Earnings → Cash'), findsNothing);
    await finish(tester);
  });

  Future<void> openTransfer(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Transfer earnings to cash'));
    await _pump(tester, 500);
    expect(find.text('Earnings → Cash'), findsOneWidget);
  }

  testWidgets('transfer presets: RN rounding, 100% equals MAX', (tester) async {
    backend.earnings = 100; // max = floor(100 / 1.18, paise) = 84.74
    await open(tester);
    await openTransfer(tester);
    expect(find.text('MAX: ₹84.7'), findsOneWidget);
    expect(find.text('0.00'), findsOneWidget);

    await tester.tap(find.text('25%'));
    await _pump(tester, 100);
    expect(find.text('21.18'), findsOneWidget); // floor(21.185)
    await tester.tap(find.text('75%'));
    await _pump(tester, 100);
    expect(find.text('63.55'), findsOneWidget);
    expect(find.text('- ₹75.0'), findsOneWidget); // 63.55 * 1.18 = 74.99
    await tester.tap(find.text('100%'));
    await _pump(tester, 100);
    expect(find.text('84.74'), findsOneWidget);
    await tester.tap(find.text('MAX'));
    await _pump(tester, 100);
    expect(find.text('84.74'), findsOneWidget);
    expect(find.text('+ ₹84.7'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('transfer failure: alert, sheet stays open', (tester) async {
    backend.transferCode = 400;
    await open(tester);
    await openTransfer(tester);
    await tester.tap(find.text('50%'));
    await _pump(tester, 100);
    await _tap(tester, find.text('CONFIRM TRANSFER'));
    await _pump(tester, 600);
    expect(find.text('Transfer Failed'), findsOneWidget);
    expect(find.text('Transfer completed successfully!'), findsNothing);
    await tester.tap(find.text('OK'));
    await _pump(tester, 400);
    expect(find.text('Earnings → Cash'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('transfer sheet closes by X and by the backdrop', (tester) async {
    await open(tester);
    await openTransfer(tester);
    await tester.tap(find.bySemanticsLabel('Close'));
    await _pump(tester, 500);
    expect(find.text('Earnings → Cash'), findsNothing);

    await openTransfer(tester);
    await tester.tapAt(const Offset(200, 40)); // backdrop above the sheet
    await _pump(tester, 500);
    expect(find.text('Earnings → Cash'), findsNothing);
    expect(
      backend.requests,
      isNot(contains('POST /api/wallet-transfer/earnings-to-cash')),
    );
    await finish(tester);
  });

  testWidgets('transfer below the minimum cannot be confirmed', (tester) async {
    backend.earnings = 10; // max 8.47 once GST is added
    await open(tester);
    await tester.tap(find.bySemanticsLabel('Transfer earnings to cash'));
    await _pump(tester, 500);
    await tester.tap(find.text('MAX'));
    await _pump(tester, 100);
    expect(find.text('8.47'), findsOneWidget);
    await _tap(tester, find.text('CONFIRM TRANSFER'));
    await _pump(tester, 400);
    expect(
      backend.requests,
      isNot(contains('POST /api/wallet-transfer/earnings-to-cash')),
    );
    await finish(tester);
  });

  testWidgets('iOS hides the cash / earnings split like RN', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await open(tester);
      expect(find.text('₹1,118.0'), findsOneWidget);
      expect(find.text('Cash'), findsNothing); // no split on iOS
      expect(find.bySemanticsLabel('Transfer earnings to cash'), findsNothing);
      await finish(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final dark in [true, false]) {
    testWidgets('${dark ? 'dark' : 'light'} theme colours', (tester) async {
      await open(tester, dark: dark);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(
        scaffold.backgroundColor,
        dark ? DarkColors.bg : LightColors.background,
      );
      final add = tester.widget<Container>(
        find
            .ancestor(of: find.text('Add money'), matching: find.byType(Container))
            .first,
      );
      // Add money: the accent gradient, on-accent text.
      expect(
        (add.decoration! as BoxDecoration).gradient!.colors.first,
        dark ? BrandColors.lime : BrandColors.purple,
      );
      expect(
        tester.widget<Text>(find.text('Add money')).style?.color,
        dark ? AppColors.black : AppColors.white,
      );
      await finish(tester);
    });
  }

  testWidgets('fits a 320 px phone, sheets included', (tester) async {
    backend.cash = 1234567.89;
    await open(tester, size: const Size(320, 568));
    expect(find.text('₹12,34,567.9'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Transfer earnings to cash'));
    await _pump(tester, 500);
    await tester.tap(find.text('75%'));
    await _pump(tester, 100);
    await tester.tap(find.bySemanticsLabel('Close'));
    await _pump(tester, 500);
    expect(find.text('Earnings → Cash'), findsNothing);

    await tester.tap(find.text('Add money'));
    await _pump(tester, 400);
    await tester.tap(find.text('₹1,500').first);
    await _pump(tester, 200);
    expect(find.text('₹1770.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  // WALLET_RENDER_DIR=<dir> flutter test test/ui/wallet_screen_test.dart
  final renderDir = Platform.environment['WALLET_RENDER_DIR'];
  group('renders', skip: renderDir == null, () {
    setUpAll(_loadFonts);
    for (final dark in [true, false]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('wallet $mode', (tester) async {
        await open(tester, size: const Size(375, 812), dark: dark);
        await _save(tester, renderDir!, 'wallet_$mode');

        await tester.tap(find.text('Add money'));
        await _pump(tester, 500);
        await tester.tap(find.text('₹500').first);
        await _pump(tester, 200);
        await _save(tester, renderDir, 'add_money_$mode');
        await tester.tap(find.bySemanticsLabel('Close'));
        await _pump(tester, 500);

        await tester.tap(find.bySemanticsLabel('Transfer earnings to cash'));
        await _pump(tester, 600);
        await tester.tap(find.text('50%'));
        await _pump(tester, 200);
        await _save(tester, renderDir, 'transfer_$mode');
        await finish(tester);
      });
    }
  });
}
