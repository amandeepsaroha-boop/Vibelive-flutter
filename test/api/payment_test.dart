import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/paymentscreen/bank_api.dart';
import 'package:vibelive/app/api/paymentscreen/billing_models.dart';
import 'package:vibelive/app/api/paymentscreen/checkout_models.dart';
import 'package:vibelive/app/api/paymentscreen/invoice_api.dart';
import 'package:vibelive/app/api/paymentscreen/payu_api.dart';
import 'package:vibelive/app/api/paymentscreen/pricing_api.dart';
import 'package:vibelive/app/api/paymentscreen/razorpay_api.dart';
import 'package:vibelive/app/api/paymentscreen/recharge_api.dart';
import 'package:vibelive/app/api/paymentscreen/transaction_api.dart';
import 'package:vibelive/app/api/paymentscreen/wallet_api.dart';
import 'package:vibelive/app/api/paymentscreen/wallet_models.dart';
import 'package:vibelive/core/config/env.dart';
import 'package:vibelive/core/network/api_client.dart';
import 'package:vibelive/core/network/api_exception.dart';

// ── Fake transport ──────────────────────────────────────────────────────────

class _Reply {
  const _Reply(this.status, [this.body = const <String, dynamic>{}]);
  final int status;
  final Object? body;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final _Reply Function(RequestOptions req) handler;
  final requests = <RequestOptions>[];

  List<String> get calls => [for (final r in requests) '${r.method} ${r.path}'];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = handler(options);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

_FakeAdapter _serve(_Reply Function(RequestOptions req) handler) {
  final adapter = _FakeAdapter(handler);
  ApiClient.dio.httpClientAdapter = adapter;
  return adapter;
}

// ── Fixtures ────────────────────────────────────────────────────────────────

Map<String, dynamic> _wallet(
  int id,
  String type,
  Object? balance, {
  Map<String, dynamic>? user,
}) => {
  'id': id,
  'documentId': 'w$id',
  'wallet_type': type,
  'balance': balance,
  'user': ?user,
};

const _payer = PayerInfo(
  id: 7,
  documentId: 'u7',
  name: 'Asha',
  email: 'asha@example.com',
  phone: '+91 98765 43210',
);

Map<String, dynamic> _nestedKeys(Map<String, dynamic> map, [String p = '']) => {
  for (final e in map.entries)
    if (e.value is Map)
      ..._nestedKeys(Map<String, dynamic>.from(e.value as Map), '$p${e.key}.')
    else
      '$p${e.key}': e.value,
};

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalletBalance', () {
    test('reads cash, earnings and the header total (Strapi v5)', () {
      final b = WalletBalance.fromResponse({
        'data': [
          _wallet(1, 'CASH_WALLET', '250.5'),
          _wallet(2, 'EARNINGS_WALLET', 100),
        ],
      });
      expect(b.cashBalance, 250.5);
      expect(b.earningsBalance, 100);
      expect(b.totalBalance, 350.5);
      expect(b.primary?.documentId, 'w1');
    });

    test('unwraps Strapi v4 attributes', () {
      final b = WalletBalance.fromResponse({
        'data': [
          {
            'id': 3,
            'attributes': {'wallet_type': 'cash_wallet', 'balance': 40},
          },
        ],
      });
      expect(b.cashWallet?.id, 3);
      expect(b.cashBalance, 40);
    });

    test('clamps cash/earnings at 0; total sums raw rows', () {
      final b = WalletBalance.fromResponse({
        'data': [
          _wallet(1, 'CASH_WALLET', -20),
          _wallet(2, 'EARNINGS_WALLET', 'abc'),
          _wallet(3, 'EARNINGS_WALLET', 999),
        ],
      });
      expect(b.cashBalance, 0);
      expect(b.earningsBalance, 0, reason: 'first earnings row wins');
      expect(b.totalBalance, -20 + 999);
    });

    test('legacy fallbacks', () {
      final legacy = WalletBalance.fromResponse({
        'data': [
          {'id': 1, 'cashBalance': 70, 'earningsBalance': 30},
        ],
      });
      expect(legacy.cashBalance, 70);
      expect(legacy.earningsBalance, 30);

      final earningsOnly = WalletBalance.fromResponse({
        'data': [_wallet(1, 'EARNINGS_WALLET', 55)],
      });
      expect(earningsOnly.cashBalance, 0, reason: 'never counted as cash');
      expect(earningsOnly.earningsBalance, 55);

      final snake = WalletBalance.fromResponse({
        'data': [
          {'id': 1, 'wallet_type': 'CASH_WALLET', 'cash_balance': '12'},
        ],
      });
      expect(snake.cashBalance, 12);
    });

    test('no wallet is an empty, zero balance', () {
      final b = WalletBalance.fromResponse({'data': <Object>[]});
      expect(b.hasWallet, isFalse);
      expect(b.totalBalance, 0);
      expect(b.cashBalance, 0);
    });

    test('malformed body fails instead of showing 0', () {
      expect(
        () => WalletBalance.fromResponse({'error': 'x'}),
        throwsA(
          isA<ApiException>().having((e) => e.type, 'type', ApiErrorType.parse),
        ),
      );
    });

    test('disk round trip', () {
      final b = WalletBalance.fromResponse({
        'data': [_wallet(1, 'CASH_WALLET', 5)],
      });
      final restored = WalletBalance.fromJson(
        jsonDecode(jsonEncode(b.toJson())),
      );
      expect(restored.cashBalance, 5);
      expect(restored.wallets.single.documentId, 'w1');
    });
  });

  group('WalletTransaction', () {
    WalletTransaction tx(Map<String, dynamic> raw) => WalletTransaction(raw);

    test('gateway top-up is a credit top-up', () {
      final t = tx({
        'transaction_Id': 'RZP_123_45',
        'amount': '500',
        'transactionType': 'Credit',
      });
      expect(t.isGatewayTopup, isTrue);
      expect(t.isCreditFor(null), isTrue);
      expect(t.kindFor(null), TransactionKind.topup);
      expect(t.amount, 500);
    });

    test('earnings → cash is a wallet transfer', () {
      final t = tx({
        'transactionType': 'transfer',
        'FromWallet': _wallet(2, 'EARNINGS_WALLET', 0),
        'to_wallet': _wallet(1, 'CASH_WALLET', 0),
      });
      expect(t.isEarningsToCash, isTrue);
      expect(t.directionFor(null), TransactionDirection.credit);
      expect(t.kindFor(null), TransactionKind.walletTransfer);
    });

    test('caller paying for a call is a debit to the receiver', () {
      final t = tx({
        'transactionType': 'call_payment',
        'FromWallet': _wallet(1, 'CASH_WALLET', 0),
        'to_wallet': _wallet(9, 'EARNINGS_WALLET', 0),
        'call': {
          'type': 'videoCall',
          'caller': {'name': 'Asha'},
          'receiver': {'name': 'Ravi'},
        },
      });
      expect(t.directionFor('Asha'), TransactionDirection.debit);
      expect(t.kindFor('Asha'), TransactionKind.paid);
      expect(t.counterpartyFor('Asha'), 'Ravi');
      expect(t.callKind, CallKind.video);
    });

    test('expert paid into earnings is a credit, not a top-up', () {
      final t = tx({
        'transactionType': 'call_payment',
        'to_wallet': _wallet(9, 'EARNINGS_WALLET', 0),
        'call': {
          'type': 'voicecall',
          'caller': {
            'data': {
              'id': 1,
              'attributes': {'name': 'Asha'},
            },
          },
        },
      });
      expect(t.isCreditFor('Ravi'), isTrue);
      expect(t.kindFor('Ravi'), TransactionKind.received);
      expect(t.counterpartyFor('Ravi'), 'Asha');
      expect(t.callKind, CallKind.audio);
    });

    test('rows without wallet types fall back to call names', () {
      final t = tx({
        'call': {
          'caller': {'name': 'Asha'},
          'receiver': {'name': 'Ravi'},
        },
      });
      expect(t.isCreditFor('Ravi'), isTrue);
      expect(t.isCreditFor('Asha'), isFalse);
      expect(t.isCreditFor(null), isFalse);
    });

    test('commission and display amount', () {
      expect(tx({'transaction_Id': 'TX9-COMM'}).isCommission, isTrue);
      final t = tx({
        'amount': 100,
        'call': {'type': 'voicecall'},
        'FromWallet': _wallet(1, 'CASH_WALLET', 0),
        'metadata': {'amountWithGST': '118', 'receiverAmount': 80},
      });
      expect(t.displayAmountFor(null), 118);
      expect(tx({'amount': 'n/a'}).displayAmountFor(null), isNull);
    });

    test('invoices from a relation or the legacy single field', () {
      expect(
        tx({
          'invoices': {
            'data': [
              {
                'id': 4,
                'attributes': {'Invoice_No': 'A'},
              },
            ],
          },
        }).invoices.single['Invoice_No'],
        'A',
      );
      expect(
        tx({
          'invoice': {'id': 5},
        }).invoices.single['id'],
        5,
      );
      expect(tx({}).invoices, isEmpty);
    });

    test('findByReference matches equal or containing references', () {
      final rows = [
        tx({'transaction_Id': 'abc'}),
        tx({'transaction_Id': 'PAYU-txn42-1'}),
      ];
      expect(
        WalletTransaction.findByReference(rows, 'txn42')?.reference,
        'PAYU-txn42-1',
      );
      expect(WalletTransaction.findByReference(rows, ''), isNull);
    });
  });

  group('RecentWalletTransfer', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    String ago(int s) =>
        now.subtract(Duration(seconds: s)).toUtc().toIso8601String();

    test('newest recent transfer touching the wallet', () {
      final wallet = Wallet(_wallet(1, 'CASH_WALLET', 0));
      final rows = [
        WalletTransaction({
          'transactionType': 'call_payment',
          'createdAt': ago(1),
          'to_wallet': _wallet(1, 'CASH_WALLET', 0),
        }),
        WalletTransaction({
          'transactionType': 'transfer',
          'createdAt': ago(5),
          'amount': '75',
          'FromWallet': _wallet(
            8,
            'CASH_WALLET',
            0,
            user: {'username': 'ravi'},
          ),
          'to_wallet': {'documentId': 'w1'},
        }),
      ];
      final r = RecentWalletTransfer.resolve(rows, wallet, now: now)!;
      expect(r.direction, TransactionDirection.credit);
      expect(r.counterpartyName, 'ravi');
      expect(r.amount, 75);
    });

    test('debit by numeric id; old or unrelated rows ignored', () {
      const wallet = Wallet({'id': 1});
      Map<String, dynamic> row(int secondsAgo, int fromId) => {
        'transactionType': 'Transfer',
        'createdAt': ago(secondsAgo),
        'FromWallet': {'id': fromId},
        'to_wallet': {
          'id': 3,
          'user': {'name': 'Meera'},
        },
      };
      expect(
        RecentWalletTransfer.resolve(
          [WalletTransaction(row(31, 1)), WalletTransaction(row(2, 2))],
          wallet,
          now: now,
        ),
        isNull,
      );
      final r = RecentWalletTransfer.resolve(
        [WalletTransaction(row(2, 1))],
        wallet,
        now: now,
      )!;
      expect(r.direction, TransactionDirection.debit);
      expect(r.counterpartyName, 'Meera');
    });

    test('preferred wallet: cash row, else first, else legacy', () {
      expect(
        Wallet.preferredOf({
          'wallets': [
            _wallet(1, 'EARNINGS_WALLET', 0),
            _wallet(2, 'CASH_WALLET', 0),
          ],
        })?.id,
        2,
      );
      expect(
        Wallet.preferredOf({
          'wallets': {
            'data': [_wallet(5, 'EARNINGS_WALLET', 0)],
          },
        })?.id,
        5,
      );
      expect(
        Wallet.preferredOf({
          'wallets': <Object>[],
          'wallet': {
            'data': {
              'id': 9,
              'attributes': {'balance': 1},
            },
          },
        })?.id,
        9,
      );
      expect(Wallet.preferredOf(null), isNull);
    });
  });

  group('billing models', () {
    test('GST breakdown and transfer limits', () {
      final g = GstBreakdown.of(100);
      expect(g.gst, 18);
      expect(g.total, 118);
      expect(GstBreakdown.of(0).total, 0);
      expect(GstBreakdown.of(-5).total, 0);
      expect(EarningsTransfer.maxTransferable(118, 18), 100);
      expect(EarningsTransfer.maxTransferable(0, 18), 0);
      expect(EarningsTransfer.isValid(100, 118, 18), isTrue);
      expect(EarningsTransfer.isValid(9.99, 118, 18), isFalse);
      expect(EarningsTransfer.isValid(101, 118, 18), isFalse);
    });

    test('GST config falls back to 18 only when IGST is unusable', () {
      expect(
        GstConfig.fromResponse({
          'data': {'IGST': '12'},
        }).igstRate,
        12,
      );
      expect(
        GstConfig.fromResponse({
          'data': {
            'id': 1,
            'attributes': {'IGST': 5},
          },
        }).igstRate,
        5,
      );
      expect(GstConfig.fromResponse({'data': null}).igstRate, 18);
      expect(
        GstConfig.fromResponse({
          'data': {'IGST': 'x'},
        }).igstRate,
        18,
      );
    });

    test('pricing config reads 0 for missing values', () {
      const p = PricingConfig({
        'Minimum_voiceCall_Rate': '10',
        'expert_verification_fees': 499,
        'Minimum_Amount_to_add_wallet': null,
      });
      expect(p.minimumVoiceRate, 10);
      expect(p.expertVerificationFees, 499);
      expect(p.minimumAmountToAddWallet, 0);
      expect(PricingConfig.empty.minimumVideoRate, 0);
    });

    test('bank detail input and reading', () {
      const input = BankDetailInput(
        userDocumentId: 'u7',
        accountName: ' Asha K ',
        accountNumber: ' 123456789 ',
        ifsc: 'sbin0001234 ',
        bankName: 'SBI',
        upiAddress: '  ',
      );
      expect(input.toJson(), {
        'user': 'u7',
        'Primary': true,
        'BankAccount': {
          'Account_Name': 'Asha K',
          'Account_Number': '123456789',
          'Account_IFSC': 'SBIN0001234',
          'Account_Bank': 'SBI',
        },
      });

      const detail = BankDetail({
        'id': 3,
        'bank_account': {'Account_Number': '9988', 'Account_IFSC': 'HDFC'},
        'UPIAccount': {'UPI_Address': 'a@upi'},
        'is_verified': true,
      });
      expect(detail.key, '3');
      expect(detail.accountNumber, '9988');
      expect(detail.upiAddress, 'a@upi');
      expect(detail.isVerified, isTrue);
    });

    test('invoice PDF URL', () {
      expect(
        InvoiceApi.pdfUrl({
          'Invoice_PDF': {'url': '/uploads/inv.pdf'},
        }),
        '${Env.apiBaseUrl}/uploads/inv.pdf',
      );
      expect(
        InvoiceApi.pdfUrl({
          'Invoice_PDF': [
            {'url': 'https://cdn.x/inv.pdf'},
          ],
        }),
        'https://cdn.x/inv.pdf',
      );
      expect(
        InvoiceApi.pdfUrl({
          'Invoice_PDF': {'data': null},
        }),
        isNull,
      );
    });
  });

  group('Razorpay checkout', () {
    test('builds SDK options from the initiate response', () {
      final c = RazorpayApi.buildCheckout(
        response: {
          'razorpayData': {'order_id': 'order_1'},
          'keyId': 'rzp_live_x',
          'amount': 59000,
          'transactionId': 'TXN1',
          'prefill': {'email': ''},
        },
        baseAmount: 500,
        payer: _payer,
        description: 'Recharge',
      );
      expect(c.orderId, 'order_1');
      expect(c.txnId, 'TXN1');
      expect(c.amountInPaise, 59000);
      expect(c.prefillContact, '9876543210');
      expect(c.prefillEmail, 'asha@example.com');
      final o = c.toOptions();
      expect(o['key'], 'rzp_live_x');
      expect(o['order_id'], 'order_1');
      expect(o['currency'], 'INR');
      expect(o['description'], 'Recharge');
      expect(o.containsKey('image'), isFalse);
      expect(o['notes'], {
        'userId': '7',
        'userDocumentId': 'u7',
        'txnId': 'TXN1',
      });
      expect(o['readonly'], {'email': true, 'contact': true, 'name': true});
    });

    test('amount: rupees under 100 become paise; none means base + GST', () {
      Map<String, dynamic> r(Object? amount) => {
        'orderId': 'o',
        'key': 'k',
        'amount': ?amount,
      };
      int paise(Object? amount, double base) => RazorpayApi.buildCheckout(
        response: r(amount),
        baseAmount: base,
        payer: _payer,
        description: 'd',
      ).amountInPaise;
      expect(paise(59, 50), 5900);
      expect(paise('5900', 50), 5900);
      expect(paise(null, 100), 11800);
      expect(paise(0, 100), 11800);
      expect(
        () => paise('abc', 100),
        throwsA(
          isA<ApiException>().having((e) => e.type, 'type', ApiErrorType.parse),
        ),
      );
    });

    test('key falls back to app-config; missing key or order fails', () {
      final c = RazorpayApi.buildCheckout(
        response: {'id': 'order_2'},
        baseAmount: 10,
        payer: const PayerInfo(),
        description: 'd',
        appConfig: {
          'data': {
            'id': 1,
            'attributes': {
              'RazorPay_Id': 'rzp_cfg',
              'RazorPay_Key_Secret': 'never-read',
            },
          },
        },
      );
      expect(c.keyId, 'rzp_cfg');
      expect(c.txnId, startsWith('RZP_'));
      expect(c.prefillName, '');
      expect(c.toOptions()['readonly'], {
        'email': false,
        'contact': false,
        'name': false,
      });

      expect(
        () => RazorpayApi.buildCheckout(
          response: {'message': 'Amount exceeds the daily limit'},
          baseAmount: 10,
          payer: _payer,
          description: 'd',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.messageKey, 'key', 'payment:errors.order_failed')
              .having(
                (e) => e.serverMessage,
                'msg',
                'Amount exceeds the daily limit',
              ),
        ),
      );
      if (Env.razorpayKeyId.isEmpty) {
        expect(
          () => RazorpayApi.buildCheckout(
            response: {'orderId': 'o'},
            baseAmount: 10,
            payer: _payer,
            description: 'd',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.messageKey,
              'key',
              'payment:errors.config_missing',
            ),
          ),
        );
      }
    });

    test('mobile cleanup', () {
      expect(RazorpayApi.cleanMobile('+91 98765 43210'), '9876543210');
      expect(RazorpayApi.cleanMobile('09876543210'), '9876543210');
      expect(RazorpayApi.cleanMobile('1234567890'), '9234567890');
      expect(RazorpayApi.cleanMobile('12345'), '12345');
      expect(RazorpayApi.cleanMobile(null), '');
    });

    test('gateway selection mapping', () {
      PaymentGateway g(Object body) =>
          PaymentGatewaySelection.fromResponse(body).gateway;
      expect(
        g({
          'data': {'paymentGateway': ' RazorPay '},
        }),
        PaymentGateway.razorpay,
      );
      expect(g({'gateway': 'razorpay'}), PaymentGateway.razorpay);
      expect(
        g({
          'data': {'paymentGateway': 'PayU'},
        }),
        PaymentGateway.payu,
      );
      expect(g(<String, dynamic>{}), PaymentGateway.payu);
    });
  });

  group('HTTP', () {
    late HttpClientAdapter original;
    setUpAll(() => original = ApiClient.dio.httpClientAdapter);
    tearDown(() => ApiClient.dio.httpClientAdapter = original);

    test('wallet lookup filters by documentId or numeric id', () async {
      final http = _serve((_) => const _Reply(200, {'data': <Object>[]}));
      await WalletApi.fetchBalance('abc123');
      await WalletApi.fetchBalance('42');
      expect(http.requests[0].path, '/api/wallets');
      expect(http.requests[0].queryParameters, {
        r'filters[user][documentId][$eq]': 'abc123',
        'populate': '*',
      });
      expect(http.requests[1].queryParameters[r'filters[user][id][$eq]'], '42');
    });

    test('transaction page filters by tab', () async {
      final http = _serve(
        (_) => const _Reply(200, {
          'data': [
            {'id': 1, 'transaction_Id': 'RZP_1'},
          ],
        }),
      );
      final rows = await TransactionApi.fetchPage(
        'u7',
        filter: TransactionFilter.cash,
        page: 2,
      );
      expect(rows.single.reference, 'RZP_1');
      final q = http.requests.single.queryParameters;
      expect(q[r'filters[$or][0][FromWallet][user][documentId][$eq]'], 'u7');
      expect(q[r'filters[$or][1][to_wallet][wallet_type][$eq]'], 'CASH_WALLET');
      expect(q['pagination[page]'], 2);
      expect(q['pagination[pageSize]'], 10);
      expect(q['sort'], 'createdAt:desc');

      await TransactionApi.fetchPage('u7');
      expect(
        http.requests.last.queryParameters.keys.where(
          (k) => k.contains('wallet_type][\$eq]'),
        ),
        isEmpty,
      );
      expect(await TransactionApi.fetchPage('  '), isEmpty);
    });

    test('recharge initiate falls back to the legacy route on 404', () async {
      final http = _serve(
        (req) => req.path.endsWith('/wallet-recharge/initiate')
            ? const _Reply(404)
            : const _Reply(200, {
                'data': {'orderId': 'o1'},
              }),
      );
      final payload = await RazorpayApi.initiateWalletRecharge(250);
      expect(payload['orderId'], 'o1');
      expect(http.calls, [
        'POST /api/razorpay/wallet-recharge/initiate',
        'POST /api/razorpay/initiate',
      ]);
      expect(http.requests.last.data, {'amount': 250.0});
    });

    test('initiate: HTTP 200 validation error is a rejection', () async {
      _serve(
        (_) => const _Reply(200, {
          'status': 'error',
          'error': {'message': 'Minimum recharge is 50 rupees'},
        }),
      );
      await expectLater(
        RazorpayApi.initiateWalletRecharge(10),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.rejected)
              .having(
                (e) => e.serverMessage,
                'msg',
                'Minimum recharge is 50 rupees',
              )
              .having(
                (e) => e.messageKey,
                'key',
                'payment:errors.recharge_failed',
              ),
        ),
      );
    });

    test('recharge re-routes once on 409', () async {
      var selections = 0;
      final http = _serve((req) {
        if (req.path.endsWith('/payment-gateway/selection')) {
          selections++;
          return _Reply(200, {
            'data': {'paymentGateway': selections == 1 ? 'razorpay' : 'payu'},
          });
        }
        if (req.path.contains('/razorpay/')) return const _Reply(409);
        return const _Reply(200, {
          'status': 'success',
          'payuUrl': 'https://secure.payu.in/_payment',
          'payuData': {'txnid': 'T9', 'hash': 'h'},
        });
      });
      final checkout = await RechargeApi.startWalletRecharge(
        const RechargeRequest(amount: 100, payer: _payer, description: 'd'),
      );
      expect(checkout, isA<PayUCheckout>());
      expect(checkout.txnId, 'T9');
      expect((checkout as PayUCheckout).payuUrl, contains('payu'));
      expect(selections, 2);
      expect(http.requests.last.data, {
        'amount': 100.0,
        'userId': 7,
        'phone': '+91 98765 43210',
        'email': 'asha@example.com',
        'udf1': '7',
      });
    });

    test(
      'selection outage defaults to Razorpay; bad amount never calls',
      () async {
        final http = _serve((req) {
          if (req.path.endsWith('/selection')) return const _Reply(404);
          return const _Reply(200, {
            'data': {'orderId': 'o5', 'keyId': 'k', 'amount': 11800},
          });
        });
        final checkout = await RechargeApi.startWalletRecharge(
          const RechargeRequest(amount: 100, payer: _payer, description: 'd'),
        );
        expect(checkout, isA<RazorpayCheckout>());
        expect((checkout as RazorpayCheckout).amountInPaise, 11800);

        final before = http.requests.length;
        await expectLater(
          RechargeApi.startWalletRecharge(
            const RechargeRequest(amount: 0, payer: _payer, description: 'd'),
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.messageKey,
              'key',
              'payment:errors.invalid_amount',
            ),
          ),
        );
        expect(http.requests.length, before);
      },
    );

    test('PayU initiate without form data fails', () async {
      _serve(
        (_) => const _Reply(200, {
          'status': 'success',
          'payuData': {'txnid': 'T1'},
        }),
      );
      await expectLater(
        PayUApi.startCheckout(amount: 10, payer: _payer),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.parse)
              .having((e) => e.messageKey, 'key', 'payment:errors.payu_failed'),
        ),
      );
    });

    group('verifyWithFallback', () {
      const payment = RazorpayPayment(
        paymentId: 'pay_1',
        orderId: 'order_1',
        signature: 'sig',
        transactionId: 'TXN1',
      );

      test('immediate success', () async {
        _serve(
          (_) => const _Reply(200, {
            'data': {'status': 'already_processed'},
          }),
        );
        final r = await RazorpayApi.verifyWithFallback(payment);
        expect(r.outcome, VerificationOutcome.success);
        expect(r.status, 'already_processed');
        expect(r.recovered, isFalse);
      });

      test('verify error → status poll recovers', () async {
        var polls = 0;
        final http = _serve((req) {
          if (req.method == 'POST') return const _Reply(400);
          polls++;
          return polls == 1
              ? const _Reply(404)
              : const _Reply(200, {
                  'data': {'paymentStatus': 'SUCCESS'},
                });
        });
        final r = await RazorpayApi.verifyWithFallback(
          payment,
          pollDelay: Duration.zero,
        );
        expect(r.outcome, VerificationOutcome.success);
        expect(r.recovered, isTrue);
        expect(http.requests.last.path, '/api/razorpay/payments/TXN1/status');
      });

      test('unconfirmed after polls is pending, not failed', () async {
        final http = _serve(
          (req) => req.method == 'POST'
              ? const _Reply(400)
              : const _Reply(200, {'status': 'created'}),
        );
        final r = await RazorpayApi.verifyWithFallback(
          payment,
          pollDelay: Duration.zero,
        );
        expect(r.outcome, VerificationOutcome.pending);
        expect(r.messageKey, 'payment:verification.pending');
        expect(http.requests.where((q) => q.method == 'GET').length, 4);
      });

      test('explicit failure or no transaction id fails', () async {
        _serve(
          (_) => const _Reply(200, {
            'status': 'failed',
            'message': 'Signature verification failed',
          }),
        );
        final r = await RazorpayApi.verifyWithFallback(payment);
        expect(r.outcome, VerificationOutcome.failed);
        expect(r.serverMessage, 'Signature verification failed');

        final http = _serve((_) => const _Reply(400));
        final r2 = await RazorpayApi.verifyWithFallback(
          const RazorpayPayment(paymentId: 'pay_2'),
        );
        expect(r2.outcome, VerificationOutcome.failed);
        expect(http.requests.single.data, {'razorpay_payment_id': 'pay_2'});
      });
    });

    test(
      'success report falls back to /razorpay/verify; never throws',
      () async {
        final http = _serve((_) => const _Reply(404));
        await RechargeApi.reportSuccess(
          const RechargeReport(
            gateway: PaymentGateway.razorpay,
            payer: _payer,
            txnId: 'TXN1',
            amount: 500,
            razorpayPaymentId: 'pay_1',
          ),
        );
        expect(http.calls, [
          'POST /api/razorpay/success',
          'POST /api/razorpay/verify',
        ]);
        final body = http.requests.first.data as Map;
        expect(body['txnid'], 'TXN1');
        expect(body['udf1'], '7');
        expect(body['status'], 'success');

        await RechargeApi.reportFailure(
          const RechargeReport(
            gateway: PaymentGateway.razorpay,
            payer: _payer,
            failureReason: {'description': 'Card declined'},
          ),
        );
        expect((http.requests.last.data as Map)['error'], 'Card declined');
      },
    );

    test('PayU reports are skipped without a txn id', () async {
      final http = _serve((_) => const _Reply(200));
      await RechargeApi.reportFailure(
        const RechargeReport(gateway: PaymentGateway.payu, payer: _payer),
      );
      expect(http.requests, isEmpty);
      await RechargeApi.reportSuccess(
        const RechargeReport(
          gateway: PaymentGateway.razorpay,
          payer: _payer,
          payuResponse: {'txnid': 'P1', 'amount': '10.00', 'hash': 'h'},
        ),
      );
      expect(http.calls, ['POST /api/payu/success']);
      expect((http.requests.single.data as Map)['amount'], '10.00');
    });

    test('pricing config: 404 → collection; both 404 → empty', () async {
      var http = _serve(
        (req) => req.path.endsWith('/pricing-config')
            ? const _Reply(404)
            : const _Reply(200, {
                'data': [
                  {
                    'id': 1,
                    'attributes': {'Minimum_videoCall_Rate': 20},
                  },
                ],
              }),
      );
      expect((await PricingApi.fetchPricingConfig()).minimumVideoRate, 20);
      expect(http.requests.last.queryParameters['pagination[pageSize]'], 1);

      _serve((_) => const _Reply(404));
      expect((await PricingApi.fetchPricingConfig()).raw, isEmpty);

      http = _serve((_) => const _Reply(403));
      await expectLater(
        PricingApi.fetchPricingConfig(),
        throwsA(isA<ApiException>()),
      );
      expect(http.requests.length, 1);
    });

    test('invoice lookup states', () async {
      final ready = await InvoiceApi.resolvePdf(
        const WalletTransaction({
          'id': 1,
          'invoices': [
            {
              'Invoice_PDF': {'url': 'https://cdn.x/a.pdf'},
            },
          ],
        }),
      );
      expect(ready.status, InvoicePdfStatus.ready);
      expect(ready.url, 'https://cdn.x/a.pdf');

      var http = _serve(
        (_) => const _Reply(200, {
          'data': [
            {'id': 3, 'Invoice_PDF': null},
          ],
        }),
      );
      final processing = await InvoiceApi.resolvePdf(
        const WalletTransaction({'id': 1, 'documentId': 'tx1'}),
      );
      expect(processing.status, InvoicePdfStatus.processing);
      expect(http.requests.single.queryParameters, {
        r'filters[$or][0][Related_Transaction][id][$eq]': 1,
        r'filters[$or][1][Related_Transaction][documentId][$eq]': 'tx1',
        'populate': '*',
      });

      http = _serve((_) => const _Reply(200, {'data': <Object>[]}));
      final generating = await InvoiceApi.resolvePdf(
        const WalletTransaction({'id': 1}),
      );
      expect(generating.status, InvoicePdfStatus.generating);
    });

    test('bank detail: PUT with a key, POST without', () async {
      final http = _serve(
        (req) => _Reply(200, {
          'data': {
            'id': 3,
            'documentId': 'b3',
            ...(req.data as Map)['data'] as Map,
          },
        }),
      );
      const base = BankDetailInput(
        userDocumentId: 'u7',
        accountName: 'Asha',
        accountNumber: '123456789',
        ifsc: 'sbin0001234',
        bankName: 'SBI',
        upiAddress: 'asha@upi',
      );
      final created = await BankApi.save(base);
      expect(created.key, 'b3');
      expect(created.ifsc, 'SBIN0001234');
      expect(created.upiAddress, 'asha@upi');
      await BankApi.save(
        const BankDetailInput(
          userDocumentId: 'u7',
          accountName: 'Asha',
          accountNumber: '123456789',
          ifsc: 'SBIN0001234',
          bankName: 'SBI',
          bankDetailKey: 'b3',
        ),
      );
      expect(http.calls, [
        'POST /api/bank-details',
        'PUT /api/bank-details/b3',
      ]);

      await expectLater(
        BankApi.save(
          const BankDetailInput(
            userDocumentId: ' ',
            accountName: 'a',
            accountNumber: '1',
            ifsc: 'i',
            bankName: 'b',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.messageKey,
            'key',
            'payment:errors.missing_user',
          ),
        ),
      );
    });

    test(
      'transfer: invalid amount never calls; errors get the transfer copy',
      () async {
        final http = _serve(
          (_) => const _Reply(400, {'message': 'insufficient'}),
        );
        await expectLater(
          WalletApi.transferEarningsToCash(double.nan),
          throwsA(isA<ApiException>()),
        );
        expect(http.requests, isEmpty);
        await expectLater(
          WalletApi.transferEarningsToCash(50),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 400)
                .having(
                  (e) => e.messageKey,
                  'key',
                  'payment:errors.transfer_failed',
                ),
          ),
        );
      },
    );

    test('recent transfer for a wallet push', () async {
      final createdAt = DateTime.now().toUtc().toIso8601String();
      final http = _serve((req) {
        if (req.path.startsWith('/api/public-users/')) {
          return const _Reply(200, {
            'data': {
              'id': 7,
              'wallets': [
                {'id': 1, 'documentId': 'w1', 'wallet_type': 'CASH_WALLET'},
              ],
            },
          });
        }
        return _Reply(200, {
          'data': [
            {
              'transactionType': 'transfer',
              'createdAt': createdAt,
              'amount': 40,
              'FromWallet': {
                'documentId': 'w1',
                'user': {'name': 'Asha'},
              },
              'to_wallet': {
                'documentId': 'w2',
                'user': {'name': 'Ravi'},
              },
            },
          ],
        });
      });
      final r = (await TransactionApi.resolveRecentTransfer('u7'))!;
      expect(r.direction, TransactionDirection.debit);
      expect(r.counterpartyName, 'Ravi');
      expect(http.requests.first.queryParameters, {
        'populate[wallet]': 'true',
        'populate[wallets]': 'true',
      });
      expect(
        http
            .requests
            .last
            .queryParameters[r'filters[$or][1][to_wallet][documentId][$eq]'],
        'w1',
      );
    });
  });

  group('i18n', () {
    final en = _nestedKeys(_readJson('assets/i18n/en/payment.json'));
    final hi = _nestedKeys(_readJson('assets/i18n/hi/payment.json'));

    test('English and Hindi have the same keys, all non-empty', () {
      expect(hi.keys.toSet(), en.keys.toSet());
      for (final v in [...en.values, ...hi.values]) {
        expect(v, isA<String>());
        expect((v as String).trim(), isNotEmpty);
      }
      expect(hi.values.every((v) => RegExp('[ऀ-ॿ]').hasMatch('$v')), isTrue);
    });

    test('every payment: key used by the API layer exists', () {
      final used = <String>{
        for (final f in Directory('lib/app/api/paymentscreen').listSync())
          if (f is File && f.path.endsWith('.dart'))
            for (final m in RegExp(
              r"'payment:([a-z_.]+[a-z_])'",
            ).allMatches(f.readAsStringSync()))
              m.group(1)!,
        for (final s in InvoicePdfStatus.values)
          if (s != InvoicePdfStatus.ready) ...[
            s.titleKey.substring('payment:'.length),
            s.messageKey.substring('payment:'.length),
          ],
      };
      expect(used, isNotEmpty);
      for (final key in used) {
        expect(en.containsKey(key), isTrue, reason: 'missing payment:$key');
      }
    });
  });
}
