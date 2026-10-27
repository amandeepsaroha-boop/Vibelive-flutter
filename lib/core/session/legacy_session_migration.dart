import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../analytics/analytics.dart';
import '../network/device_info.dart';
import '../storage/app_prefs.dart';
import '../utils/log.dart';
import 'session_store.dart';

/// One-time handover of the React Native build's session, so the store update
/// from RN to Flutter logs nobody out. Runs in `main()` before
/// [SessionStore.restore].
///
/// The native readers (`LegacySessionReader` on Android and iOS) only read:
/// RN's own data is never changed or deleted. What carries over:
///  * the tokens — RN's secure store first (the copy RN itself trusted), its
///    AsyncStorage mirror when that is empty;
///  * the user and expert records;
///  * RN's device id, so token refresh and push keep the same device on the
///    backend (sessions are tied to it);
///  * "language question answered / skipped" per user.
///
/// Marked done once it has run to the end: after a migration, when there is
/// nothing to migrate, or when Flutter already has a session (never
/// overwritten). Not marked when the data couldn't be read yet (locked
/// iPhone, a read error), so the next launch tries again.
abstract final class LegacySessionMigration {
  static const _channel = MethodChannel(
    'com.angrymamba.vibelive/legacy_session',
  );
  static const _tag = 'LegacySession';
  static const doneKey = 'rn_session_migrated_v1';

  static Future<void> run() async {
    if (AppPrefs.getString(doneKey) != null) return;
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('read')
          .timeout(const Duration(seconds: 6));
    } on MissingPluginException {
      return; // no reader in this engine (tests, a background isolate)
    } catch (e) {
      Log.w(_tag, 'read failed, retrying next launch: $e');
      return;
    }
    if (raw == null) return;
    try {
      await _apply(raw);
    } catch (e) {
      Log.w(_tag, 'migration failed, retrying next launch: $e');
      Analytics.log('rn_session_migration', {
        'result': 'error',
        'reason': '$e',
      });
    }
  }

  static Future<void> _apply(Map<Object?, Object?> raw) async {
    final secure = _strings(raw['secure']);
    final async = _strings(raw['async']);
    final locked = raw['locked'] == true;
    final errors = raw['errors'] is List
        ? (raw['errors'] as List).join(',')
        : '';

    // Even a signed-out user keeps their answers.
    for (final e in async.entries) {
      if (e.key.startsWith('@language_step_done:')) {
        await AppPrefs.setString(e.key.substring(1), e.value);
      }
    }

    // Flutter already signed someone in: theirs is newer, keep it — and keep
    // the device id that session was created with. Adopting RN's id here
    // (a first launch whose read failed, then a fresh login) moved every
    // later token sync to an id the live session doesn't have, so its push
    // token never reached the session a call rings.
    if (AppPrefs.getString('session_user') != null) {
      return _done('flutter_session');
    }

    // Signed out: keep the RN device identity.
    await _adoptDeviceId(async['device_id']);

    final access = secure['access_token'] ?? async['access_token'];
    final refresh = secure['refresh_token'] ?? async['refresh_token'];
    final user = _json(async['auth_user']);
    final hasUser =
        user != null && (user['documentId'] != null || user['id'] != null);
    if (access == null || !hasUser) {
      // Data that exists but can't be read yet: try again next launch.
      if (locked || (errors.isNotEmpty && access == null && refresh != null)) {
        Log.w(_tag, 'not readable yet (locked=$locked $errors)');
        return;
      }
      return _done(access == null ? 'no_session' : 'no_user');
    }

    await SessionStore.instance.signIn(
      user: user,
      accessToken: access,
      refreshToken: refresh,
      expert: _json(async['auth_expert']),
    );
    Log.d(_tag, 'RN session carried over');
    await _done(
      'migrated',
      source: secure['access_token'] != null ? 'secure' : 'async',
    );
  }

  /// RN sends `deviceId` as is (`android-…`, `ios-…`); [DeviceInfo] then
  /// sends the very same id.
  static Future<void> _adoptDeviceId(String? id) async {
    if (id == null || id.isEmpty) return;
    if (AppPrefs.getString(DeviceInfo.legacyDeviceIdKey) != null) return;
    await AppPrefs.setString(DeviceInfo.legacyDeviceIdKey, id);
  }

  static Future<void> _done(String result, {String? source}) async {
    await AppPrefs.setString(doneKey, result);
    Analytics.log('rn_session_migration', {'result': result, 'source': source});
  }

  static Map<String, String> _strings(Object? value) => {
    if (value is Map)
      for (final e in value.entries)
        if (e.key is String &&
            e.value is String &&
            (e.value as String).isNotEmpty)
          e.key as String: e.value as String,
  };

  static Map<String, dynamic>? _json(String? text) {
    if (text == null) return null;
    try {
      final v = jsonDecode(text);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
