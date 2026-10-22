import 'package:shared_preferences/shared_preferences.dart';

/// Shared preferences with an in-memory cache, loaded once before `runApp`
/// so every later read is synchronous (theme, language, cached queries).
abstract final class AppPrefs {
  static SharedPreferencesWithCache? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
  }

  static SharedPreferencesWithCache get instance {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('AppPrefs.init() must run before use');
    }
    return prefs;
  }

  static String? getString(String key) {
    try {
      return instance.getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setString(String key, String value) async {
    try {
      await instance.setString(key, value);
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    try {
      await instance.remove(key);
    } catch (_) {}
  }

  static Iterable<String> keysWithPrefix(String prefix) {
    try {
      return instance.keys.where((k) => k.startsWith(prefix)).toList();
    } catch (_) {
      return const [];
    }
  }
}
