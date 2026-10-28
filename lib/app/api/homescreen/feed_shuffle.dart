import 'dart:math';

import 'package:flutter/foundation.dart';

import '../listingflow/listing_models.dart';

/// Discover's hosts arrive ranked, a page at a time; inside each page the
/// order is shuffled, so the hosts of one page take turns at its top while
/// the pages keep their rank. The order is a hash of each host's id with a
/// seed: it holds across background re-fetches and the launch copy (cards
/// never jump under the finger) and changes on pull-to-refresh ([reseed])
/// and on each launch.
abstract final class FeedShuffle {
  static int _seed = _newSeed();

  /// Tests pin the order to the server's.
  @visibleForTesting
  static bool enabled = true;

  /// A new order for the next fetch (pull-to-refresh).
  static void reseed() => _seed = _newSeed();

  /// [hosts] in this seed's order (the server's when disabled).
  static List<HostCard> within(List<HostCard> hosts) {
    if (!enabled || hosts.length < 2) return hosts;
    final ranked = [for (final h in hosts) (_rank(h), h)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, h) in ranked) h];
  }

  /// FNV-1a over the id, salted with the seed.
  static int _rank(HostCard h) {
    var x = 0x811c9dc5 ^ _seed;
    for (final c in (h.documentId ?? '${h.id}').codeUnits) {
      x = ((x ^ c) * 0x01000193) & 0xffffffff;
    }
    return x;
  }

  static int _newSeed() => Random().nextInt(1 << 32);
}
