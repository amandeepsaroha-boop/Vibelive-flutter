import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/log.dart';

/// Small durable facts the native / push layer shares across isolates (the
/// UI isolate, the Android FCM background isolate and the CallKit background
/// isolate). `SharedPreferencesAsync` reads the platform every time, so a
/// value one isolate wrote is never hidden behind another's cache. Never
/// throws.
abstract final class NativeCallMarks {
  static const _appEndedKey = 'push_native_app_ended_v1';
  static const _endedKey = 'push_native_ended_v1';
  static const _rungKey = 'push_native_rung_v1';
  static const _connectedKey = 'push_native_connected_v1';
  static const _inviteKey = 'push_native_last_invite_v1';
  static const _ackedKey = 'push_native_acked_v1';

  /// How long an app-initiated end suppresses the plugin's DECLINE / ENDED
  /// echo.
  static const appEndedWindow = Duration(minutes: 2);
  static const endedWindow = Duration(minutes: 10);
  static const rungWindow = Duration(minutes: 2);
  static const connectedWindow = Duration(hours: 4);

  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  // ── per-call timestamps ────────────────────────────────────────────────

  /// The app (not the user) ended the plugin call: the plugin's DECLINE /
  /// ENDED echo must never send `/call/Callend` (a Callend on a call another
  /// device answered completes and bills it).
  static Future<void> markAppEnded(String callId) =>
      _stamp(_appEndedKey, callId, appEndedWindow);
  static Future<bool> isAppEnded(String callId) =>
      _within(_appEndedKey, callId, appEndedWindow);

  /// The backend said the call is over: never ring it.
  static Future<void> markEnded(String callId) =>
      _stamp(_endedKey, callId, endedWindow);
  static Future<bool> isEnded(String callId) =>
      _within(_endedKey, callId, endedWindow);

  /// The Android ringer was shown for this call.
  static Future<void> markRung(String callId) =>
      _stamp(_rungKey, callId, rungWindow);
  static Future<bool> wasRung(String callId) =>
      _within(_rungKey, callId, rungWindow);

  /// The FCM background isolate sent the ringing ack for this call: the UI
  /// isolate (notification tap, adopted ring) must not send it again.
  static Future<void> markAcked(String callId) =>
      _stamp(_ackedKey, callId, rungWindow);
  static Future<bool> wasAcked(String callId) =>
      _within(_ackedKey, callId, rungWindow);

  /// The call connected at [at] (a background Hang up reports `completed`).
  static Future<void> markConnected(String callId, DateTime at) =>
      _stamp(_connectedKey, callId, connectedWindow, at: at);
  static Future<DateTime?> connectedAt(String callId) async {
    final map = await _readMap(_connectedKey);
    final ms = map[callId];
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> clearConnected(String callId) =>
      _remove(_connectedKey, callId);

  // ── payloads ───────────────────────────────────────────────────────────

  /// The last invite the Android ringer showed (a notification tap opens it).
  static Future<void> saveInvite(String callId, Map<String, dynamic> data) =>
      _setJson(_inviteKey, {'callId': callId, 'data': data});

  static Future<Map<String, dynamic>?> invite(String callId) async {
    final m = await _getJson(_inviteKey);
    if (m == null || m['callId'] != callId) return null;
    final data = m['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  // ──────────────────────────────────────────────────────────────────────

  static Future<void> _stamp(
    String key,
    String callId,
    Duration keep, {
    DateTime? at,
  }) async {
    if (callId.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = await _readMap(key)
      ..removeWhere((_, ms) => now - ms > keep.inMilliseconds)
      ..[callId] = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await _setJson(key, map);
  }

  static Future<bool> _within(String key, String callId, Duration keep) async {
    if (callId.isEmpty) return false;
    final ms = (await _readMap(key))[callId];
    return ms != null &&
        DateTime.now().millisecondsSinceEpoch - ms <= keep.inMilliseconds;
  }

  static Future<void> _remove(String key, String callId) async {
    final map = await _readMap(key);
    if (map.remove(callId) != null) await _setJson(key, map);
  }

  static Future<Map<String, int>> _readMap(String key) async {
    final m = await _getJson(key);
    return {
      for (final e in (m ?? const {}).entries)
        if (e.value is int) e.key: e.value as int,
    };
  }

  static Future<Map<String, dynamic>?> _getJson(String key) async {
    try {
      final raw = await _prefs.getString(key);
      if (raw == null) return null;
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _setJson(String key, Map<String, dynamic> value) async {
    try {
      await _prefs.setString(key, jsonEncode(value));
    } catch (e) {
      Log.w('NativeCallMarks', '$key: $e');
    }
  }
}
