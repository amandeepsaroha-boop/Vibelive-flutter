import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_models.dart';

/// One feed row: a full-width featured card, or one / two regular cards.
class DiscoverRow {
  const DiscoverRow(this.hosts, {this.featured = false});

  final List<HostCard> hosts;
  final bool featured;

  /// Row height, without the 12 gap under it.
  static double heightOf({required bool featured}) =>
      featured ? 270.ms : 250.ms;

  /// Fixed per kind, so the list never measures a row.
  double get height => heightOf(featured: featured);

  /// A pair row still waiting for its second card.
  bool get isHalf => !featured && hosts.length == 1;

  /// Stable across pages: a half row keeps its key when its second card
  /// lands.
  String get key => '${featured ? 'f' : 'p'}:${hosts.first.id}';

  bool _sameAs(DiscoverRow o) {
    if (o.featured != featured || o.hosts.length != hosts.length) {
      return false;
    }
    for (var i = 0; i < hosts.length; i++) {
      if (!identical(o.hosts[i], hosts[i])) return false;
    }
    return true;
  }
}

/// What the next page adds first, shown as skeleton while it loads.
class DiscoverNext {
  const DiscoverNext({
    this.fillsSlot = false,
    this.featured = false,
    this.cards = 0,
  });

  /// The last row is a half pair: the next card lands in its empty slot.
  final bool fillsSlot;

  /// The row after it is a featured (full-width) card.
  final bool featured;

  /// Cards in the row after it: 0 (none), 1 or 2.
  final int cards;
}

/// [DiscoverLayout.plan]'s result: the rows, and where the layout stands
/// for the next page.
class DiscoverPlan {
  const DiscoverPlan(
    this.rows, {
    this.heldFeatured = 0,
    this.sinceFeatured = 0,
  });

  final List<DiscoverRow> rows;

  /// Featured cards waiting for their slot (more pages coming).
  final int heldFeatured;

  /// Regular cards placed since the last featured row.
  final int sinceFeatured;

  /// The shape [incoming] more cards take first (they're assumed regular:
  /// a page's featured cards aren't known before it lands).
  DiscoverNext next(int incoming) {
    if (incoming <= 0 || rows.isEmpty) return const DiscoverNext();
    var left = incoming;
    var since = sinceFeatured;
    final fillsSlot = rows.last.isHalf;
    if (fillsSlot) {
      left--;
      since++;
    }
    if (left <= 0) return DiscoverNext(fillsSlot: fillsSlot);
    if (since >= DiscoverLayout.featuredEvery && heldFeatured > 0) {
      return DiscoverNext(fillsSlot: fillsSlot, featured: true, cards: 1);
    }
    return DiscoverNext(fillsSlot: fillsSlot, cards: left >= 2 ? 2 : 1);
  }
}

/// Feed layout (RN `vibescreen` `layoutRows`): the first card is featured,
/// then pairs, with one featured card injected after every 10 regular ones.
abstract final class DiscoverLayout {
  static const featuredEvery = 10;

  /// [holdLeftoverFeatured]: more pages are coming on the plain feed, so
  /// spare featured cards wait for their slot instead of piling up at the
  /// end and jumping into the middle when the next page lands.
  static List<DiscoverRow> rows(
    List<HostCard> hosts, {
    required bool holdLeftoverFeatured,
  }) => plan(hosts, holdLeftoverFeatured: holdLeftoverFeatured).rows;

  /// [rows], plus the state the next page continues from. Rows equal to one
  /// in [previous] (same kind, same card objects) are that very object, so
  /// a new page leaves the rows already on screen untouched.
  static DiscoverPlan plan(
    List<HostCard> hosts, {
    required bool holdLeftoverFeatured,
    List<DiscoverRow> previous = const [],
  }) {
    final featured = [
      for (final h in hosts)
        if (h.isFeatured) h,
    ];
    final normal = [
      for (final h in hosts)
        if (!h.isFeatured) h,
    ];
    if (featured.isEmpty && normal.isNotEmpty) featured.add(normal.removeAt(0));

    final rows = <DiscoverRow>[];
    void add(DiscoverRow row) {
      final i = rows.length;
      rows.add(
        i < previous.length && previous[i]._sameAs(row) ? previous[i] : row,
      );
    }

    var f = 0, n = 0, sinceFeatured = 0;
    if (f < featured.length) {
      add(DiscoverRow([featured[f++]], featured: true));
    }
    while (n < normal.length) {
      if (sinceFeatured >= featuredEvery && f < featured.length) {
        add(DiscoverRow([featured[f++]], featured: true));
        sinceFeatured = 0;
        continue;
      }
      final pair = normal.skip(n).take(2).toList();
      add(DiscoverRow(pair));
      n += pair.length;
      sinceFeatured += pair.length;
    }
    while (!holdLeftoverFeatured && f < featured.length) {
      add(DiscoverRow([featured[f++]], featured: true));
    }
    return DiscoverPlan(
      rows,
      heldFeatured: featured.length - f,
      sinceFeatured: sinceFeatured,
    );
  }
}
