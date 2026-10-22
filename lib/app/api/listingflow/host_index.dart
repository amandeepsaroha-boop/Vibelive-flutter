import '../../../core/query/query_hooks.dart';
import 'listing_keys.dart';
import 'listing_models.dart';

/// A host found in [HostIndex]; [fresh] = fetched within
/// [HostIndex.freshFor] and not invalidated since.
typedef HostHit = ({HostCard card, bool fresh});

/// Every full host card fetched this session (Discover, Popular, search,
/// profile lookups), under each id it can be looked up by: expert-profile
/// documentId, user documentId, numeric user id and handler. A profile
/// opened from any list, link or call log renders from here at once; only a
/// host never seen this session waits for the network.
///
/// Lives in the query cache under [ListingKeys.hostIndex], so logout clears
/// it and a write that invalidates the listings (block, review) marks every
/// entry stale (still shown, then refreshed).
abstract final class HostIndex {
  static const freshFor = StaleTime.medium;
  static const _max = 600;

  /// Keeps the cards that carry the full profile ([HostCard.hasFullProfile]).
  static void seed(Iterable<HostCard> hosts) {
    final full = [
      for (final h in hosts)
        if (h.hasFullProfile) h,
    ];
    if (full.isEmpty) return;
    final store = _store();
    final now = DateTime.now();
    for (final h in full) {
      final entry = (card: h, at: now);
      for (final id in _ids(h)) {
        store.remove(id); // re-insert: most recent last
        store[id] = entry;
      }
    }
    while (store.length > _max) {
      store.remove(store.keys.first);
    }
  }

  /// The host behind any of these ids (first match, most specific id first).
  static HostHit? find({
    String? expertDocumentId,
    String? userDocumentId,
    String? userId,
    String? handler,
  }) {
    final store = _peekStore();
    if (store == null) return null;
    for (final id in [
      if (_clean(userDocumentId) case final v?) 'u:$v',
      if (_clean(expertDocumentId) case final v?) 'e:$v',
      if (_clean(userId) case final v?) 'n:$v',
      if (_clean(handler) case final v?) 'h:${v.toLowerCase()}',
    ]) {
      final entry = store[id];
      if (entry != null) {
        final fresh = DateTime.now().difference(entry.at) < freshFor;
        return (card: entry.card, fresh: fresh);
      }
    }
    return null;
  }

  /// A shared link / `openUserId` target: a user or expert-profile
  /// documentId, a numeric user id or a handler.
  static HostHit? findLink(String target) {
    final t = target.trim();
    if (t.isEmpty) return null;
    final numeric = int.tryParse(t) != null;
    return find(
      userDocumentId: numeric ? null : t,
      expertDocumentId: numeric ? null : t,
      userId: numeric ? t : null,
      handler: t,
    );
  }

  static Iterable<String> _ids(HostCard h) sync* {
    if (_clean(h.userDocumentId) case final v?) yield 'u:$v';
    if (_clean(h.expertProfileDocumentId) case final v?) yield 'e:$v';
    if (h.receiverId case final v?) yield 'n:$v';
    if (_clean(h.handler) case final v?) yield 'h:${v.toLowerCase()}';
  }

  static String? _clean(String? v) {
    final t = v?.trim();
    return t == null || t.isEmpty ? null : t;
  }

  static _Entries? _peekStore() {
    final query = queryCache.entry<_Entries>(ListingKeys.hostIndex);
    final store = query?.data;
    if (store != null && query!.isInvalidated) _expire(store);
    return store;
  }

  static _Entries _store() {
    final existing = _peekStore();
    final invalidated =
        queryCache.entry<_Entries>(ListingKeys.hostIndex)?.isInvalidated ??
        false;
    if (existing != null && !invalidated) return existing;
    final store = existing ?? <String, _Entry>{};
    // Creates the entry, or clears its invalidated flag (entries expired).
    queryCache.setQueryData<_Entries, ApiException>(
      ListingKeys.hostIndex,
      (_) => store,
    );
    return store;
  }

  /// Every entry becomes stale (shown, then refreshed).
  static void _expire(_Entries store) {
    final old = DateTime.fromMillisecondsSinceEpoch(0);
    store.updateAll((_, e) => (card: e.card, at: old));
  }
}

typedef _Entry = ({HostCard card, DateTime at});
typedef _Entries = Map<String, _Entry>;
