import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/navbar/topbar/home_top_bar.dart';

void main() {
  test('compactAmount: rupees below 1,000, then k, never rounded up', () {
    expect(compactAmount(0), '0');
    expect(compactAmount(120), '120');
    expect(compactAmount(120.55), '120.5');
    expect(compactAmount(999.99), '999.9');
    expect(compactAmount(1000), '1k');
    expect(compactAmount(1299), '1.2k');
    expect(compactAmount(10000), '10k');
    expect(compactAmount(10999), '10.9k');
    expect(compactAmount(150000), '150k');
  });
}
