import 'dart:async';
import 'dart:convert';

import 'package:fquery_core/fquery_core.dart';

import '../storage/app_prefs.dart';
import '../utils/log.dart';

/// Disk copy of selected queries (RN `app-cache.store.js`): screens render
/// the last known data instantly on launch while the network refetches.
///
/// Only for small, JSON-encodable results (profile, wallet, app-config…).
abstract final class QueryPersist {
  static const _prefix = 'qcache:';

  static String _storageKey(RawQueryKey key) => '$_prefix${jsonEncode(key)}';

  static T? read<T>(RawQueryKey key, T Function(Object? json) fromJson) {
    final storageKey = _storageKey(key);
    final raw = AppPrefs.getString(storageKey);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (e) {
      // Shape changed between versions: drop the stale copy.
      Log.w('QueryPersist', 'discarding $storageKey: $e');
      unawaited(AppPrefs.remove(storageKey));
      return null;
    }
  }

  static void write(RawQueryKey key, Object? json) {
    try {
      unawaited(AppPrefs.setString(_storageKey(key), jsonEncode(json)));
    } catch (e) {
      Log.w('QueryPersist', 'not persisted ${jsonEncode(key)}: $e');
    }
  }

  static void remove(RawQueryKey key) =>
      unawaited(AppPrefs.remove(_storageKey(key)));

  /// Logout: wipe every persisted query.
  static Future<void> clearAll() async {
    for (final k in AppPrefs.keysWithPrefix(_prefix)) {
      await AppPrefs.remove(k);
    }
  }
}
