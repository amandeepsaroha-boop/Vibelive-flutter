import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/paymentscreen/wallet_models.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/razorpay_gateway.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/transaction_pager.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/wallet_amounts.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/wallet_format.dart';
import 'package:vibelive/core/network/api_exception.dart';

WalletTransaction _row(int i) =>
    WalletTransaction({'id': i, 'transaction_Id': 'T$i'});

void main() {
  test('add-money input follows the RN sanitizer', () {
    expect(TopUpAmount.sanitize('1a2b3'), '123');
    expect(TopUpAmount.sanitize('12.345'), '12.34');
    expect(TopUpAmount.sanitize('1.2.3'), '1.2');
    expect(TopUpAmount.sanitize('007'), '7');
    expect(TopUpAmount.sanitize('0.5'), '0.5');
    expect(TopUpAmount.presetFor('500'), 500);
    expect(TopUpAmount.presetFor('500.0'), isNull);
    expect(TopUpAmount.presetFor('501'), isNull);
    expect(TopUpAmount.effective('', 100), 100);
    expect(TopUpAmount.effective('5.', null), 5);
    expect(TopUpAmount.effective('.', null), 0);
    expect(TopUpAmount.breakdown(100).total, closeTo(118, 1e-9));
  });

  test('transfer quote: max, presets, GST and limits', () {
    const q = TransferQuote(amountText: '', earnings: 236, gstPercent: 18);
    expect(q.max, 200);
    expect(q.presetText(25), '50');
    expect(q.presetText(75), '150');
    expect(q.maxText, '200');
    final half = q.withAmount('100');
    expect(half.gst, closeTo(18, 1e-9));
    expect(half.debit, closeTo(118, 1e-9));
    expect(half.isValid, isTrue);
    expect(q.withAmount('9.99').belowMinimum, isTrue);
    expect(q.withAmount('9.99').isValid, isFalse);
    expect(q.withAmount('201').exceedsEarnings, isTrue);
    // Nothing to move: presets stay empty.
    const none = TransferQuote(amountText: '', earnings: 0, gstPercent: 18);
    expect(none.presetText(50), '');
    expect(none.maxText, '');
  });

  test('formatting matches RN en-IN / en-US output', () {
    expect(WalletFormat.amount(1234567.89), '12,34,567.9');
    expect(WalletFormat.amount2(1234.5), '1,234.50');
    expect(WalletFormat.whole(1500), '1,500');
    expect(WalletFormat.js(12.0), '12');
    expect(WalletFormat.js(12.5), '12.5');
    final at = WalletFormat.dateTime(DateTime(2026, 10, 5, 15, 4));
    expect(at.date, 'Oct 05, 2026');
    expect(at.time, '3:04 PM');
  });

  test('checkout errors: cancel detection and JSON descriptions', () {
    expect(NativeRazorpayGateway.isCancel(2, null), isTrue);
    expect(NativeRazorpayGateway.isCancel(0, 'Payment Cancelled'), isTrue);
    expect(NativeRazorpayGateway.isCancel(0, 'Card declined'), isFalse);
    expect(
      NativeRazorpayGateway.errorDescription(
        '{"error":{"code":"BAD_REQUEST_ERROR","description":"Card declined"}}',
      ),
      'Card declined',
    );
    expect(NativeRazorpayGateway.errorDescription('Oops'), 'Oops');
    expect(NativeRazorpayGateway.errorDescription(' '), isNull);
  });

  test('pager: pages of 10, short page ends, late answers dropped', () async {
    final calls = <String>[];
    final pager = TransactionPager(
      cached: (_) => null,
      load: (filter, page, {required fresh}) async {
        calls.add('${filter.name}:$page:$fresh');
        final count = page == 1 ? 10 : 4;
        return [for (var i = 0; i < count; i++) _row(page * 100 + i)];
      },
    );
    await pager.select(TransactionFilter.all);
    expect(pager.value.rows, hasLength(10));
    expect(pager.value.hasMore, isTrue);
    await pager.loadMore();
    expect(pager.value.rows, hasLength(14));
    expect(pager.value.hasMore, isFalse);
    await pager.loadMore(); // nothing more to load
    expect(calls, ['all:1:true', 'all:2:false']);

    // A tab switch while page 1 of the old tab is still loading.
    final old = pager.refresh();
    await pager.select(TransactionFilter.cash);
    await old;
    expect(pager.value.filter, TransactionFilter.cash);
    pager.dispose();
  });

  test('pager: a failed first page offers a retry', () async {
    final pager = TransactionPager(
      cached: (_) => null,
      load: (_, _, {required fresh}) async =>
          throw const ApiException(ApiErrorType.network),
    );
    await pager.select(TransactionFilter.all);
    expect(pager.value.loading, isFalse);
    expect(pager.value.error?.type, ApiErrorType.network);
    pager.dispose();
  });
}
