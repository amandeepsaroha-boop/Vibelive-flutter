import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/homescreen/feed_shuffle.dart';
import 'package:vibelive/app/api/listingflow/listing_models.dart';

List<HostCard> _page(int n) => [
  for (var i = 0; i < n; i++)
    HostCard.fromJson({'id': i + 1, 'documentId': 'host$i'}, index: i),
];

List<String?> _ids(List<HostCard> hosts) => [
  for (final h in hosts) h.documentId,
];

void main() {
  tearDown(() => FeedShuffle.enabled = true);

  test('a page is reordered, never changed, and holds until a reseed', () {
    final page = _page(16);
    final once = FeedShuffle.within(page);
    expect(once.toSet(), page.toSet()); // same hosts, nobody added or lost
    // A background re-fetch (same seed, rows in any order) keeps the order.
    expect(_ids(FeedShuffle.within(page.reversed.toList())), _ids(once));

    var changed = false;
    for (var i = 0; i < 5 && !changed; i++) {
      FeedShuffle.reseed();
      changed = !listEquals(_ids(FeedShuffle.within(page)), _ids(once));
    }
    expect(changed, isTrue, reason: 'pull-to-refresh gives a new order');
  });

  test('across refreshes every host takes a turn at the top', () {
    final page = _page(10);
    final firsts = <String?>{};
    for (var i = 0; i < 300; i++) {
      FeedShuffle.reseed();
      firsts.add(FeedShuffle.within(page).first.documentId);
    }
    expect(firsts.length, 10);
  });

  test('disabled: the server order', () {
    FeedShuffle.enabled = false;
    final page = _page(8);
    expect(_ids(FeedShuffle.within(page)), _ids(page));
  });
}
