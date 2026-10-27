import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/component/infinite_scroll.dart';
import 'package:vibelive/app/paymentscreen/wallet/helper/bank_form.dart';
import 'package:vibelive/core/theme/app_theme.dart';
import 'package:vibelive/core/utils/scale.dart';

Map<BankField, String> _validate({
  String holder = 'Asha Verma',
  String bank = 'State Bank of India',
  String number = '123456789012',
  String? confirm,
  String ifsc = 'SBIN0001234',
  String upi = '',
}) => BankForm.validate(
  holder: holder,
  bank: bank,
  number: number,
  confirm: confirm ?? number,
  ifsc: ifsc,
  upi: upi,
);

void main() {
  group('BankForm', () {
    test('a complete form passes', () => expect(_validate(), isEmpty));

    test('enforces the backend component rules', () {
      expect(_validate(holder: 'Asha 1').keys, [BankField.holder]);
      expect(_validate(bank: 'S').keys, [BankField.bank]);
      expect(_validate(number: '12345678').keys, [BankField.number]);
      expect(_validate(confirm: '999999999').keys, [BankField.confirm]);
      // The fifth IFSC character is always 0.
      expect(_validate(ifsc: 'SBIN1001234').keys, [BankField.ifsc]);
      // Typed in lower case, saved upper case (BankDetailInput).
      expect(_validate(ifsc: 'sbin0001234'), isEmpty);
      expect(_validate(upi: 'asha').keys, [BankField.upi]);
      expect(_validate(upi: 'asha@okhdfc'), isEmpty);
    });

    test('shows only the last four digits', () {
      expect(BankForm.masked('123456789012'), '••••••••9012');
      expect(BankForm.masked(null), '');
    });
  });

  testWidgets('loadAhead asks early, and again when a page lands short', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Scale.update(const Size(400, 800));
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var asks = 0;

    Widget list({required int rows, bool loading = false}) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: InfiniteScroll(
          controller: controller,
          hasMore: true,
          loadingMore: loading,
          onLoadMore: () => asks++,
          loadAhead: 2.5,
          slivers: [
            SliverFixedExtentList.builder(
              itemExtent: 100,
              itemCount: rows,
              itemBuilder: (_, i) => Text('row $i'),
            ),
          ],
        ),
      ),
    );

    // 50 rows (5,000 px) in an 800 px viewport: 2.5 viewports is 2,000 px.
    await tester.pumpWidget(list(rows: 50));
    controller.jumpTo(100); // 4,100 px still below
    await tester.pump();
    expect(asks, 0);

    controller.jumpTo(2500); // 1,700 px below: ask, long before the end
    await tester.pump();
    expect(asks, 1);
    expect(find.text('row 49'), findsNothing);

    // The page lands with two rows: 1,900 px below, still inside the
    // look-ahead. The next page is asked for with no scroll at all.
    await tester.pumpWidget(list(rows: 50, loading: true));
    await tester.pumpWidget(list(rows: 52));
    await tester.pump();
    expect(asks, 2);
  });
}
