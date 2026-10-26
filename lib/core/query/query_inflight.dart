import 'dart:convert';

import 'package:fquery_core/fquery_core.dart' show RawQueryKey;

/// One network request per query key at a time, shared by the hooks and
/// `queryCache.fetchQuery`: a screen mounting while a prefetch (or another
/// screen) is loading the same key joins that request instead of sending a
/// second one.
abstract final class QueryInflight {
  static final _pending = <String, Future<Object?>>{};

  static String id(RawQueryKey key) => jsonEncode(key);

  /// [fetch] for [key], or the request already running for it. [fresh]
  /// never joins (a forced refresh must not get an answer sent before it).
  static Future<T> run<T>(
    RawQueryKey key,
    Future<T> Function() fetch, {
    bool fresh = false,
  }) {
    final k = id(key);
    final running = _pending[k];
    if (!fresh && running != null) return running.then((v) => v as T);
    final future = fetch();
    _pending[k] = future;
    void done() {
      if (identical(_pending[k], future)) _pending.remove(k);
    }

    future.then((_) => done(), onError: (Object _) => done());
    return future;
  }

  static final _invalidatedAt = <String, DateTime>{};

  /// When a key under [key]'s prefixes was last invalidated (a write), or
  /// null. Data stored before that is stale even while its entry's own flag
  /// is not set yet (`invalidateAll` flags keys one by one, and a flagged
  /// query refetches at once: a read it composes must not count as fresh).
  static DateTime? invalidatedAt(RawQueryKey key) {
    if (_invalidatedAt.isEmpty) return null;
    final k = id(key);
    DateTime? latest;
    _invalidatedAt.forEach((prefix, at) {
      if (k.startsWith(prefix) && (latest == null || at.isAfter(latest!))) {
        latest = at;
      }
    });
    return latest;
  }

  /// After a write: requests under these prefixes were sent before it, so
  /// the next read starts a new one instead of joining them; data stored
  /// before now is stale ([invalidatedAt]).
  static void forget(Iterable<RawQueryKey> prefixes) {
    final now = DateTime.now();
    for (final p in prefixes) {
      if (p.isEmpty) continue;
      final s = id(p);
      _invalidatedAt[s.substring(0, s.length - 1)] = now;
    }
    if (_pending.isEmpty) return;
    // `["a","b"` (no closing bracket) prefixes every key starting a, b.
    final ids = [
      for (final p in prefixes)
        if (id(p) case final s when p.isNotEmpty) s.substring(0, s.length - 1),
    ];
    _pending.removeWhere((k, _) => ids.any(k.startsWith));
  }

  /// Logout.
  static void clear() {
    _pending.clear();
    _invalidatedAt.clear();
  }
}
