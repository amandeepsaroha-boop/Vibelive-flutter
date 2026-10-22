import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/log.dart';
import 'call_constants.dart';

/// A system-UI accept the UI isolate has not acted on yet.
typedef PendingAccept = ({
  Map<String, dynamic> payload,
  DateTime at,
  bool apiDone,
});

/// The durable half of the call state: what must survive a restart or
/// cross an isolate (the Android FCM / CallKit background isolate writes,
/// the UI isolate reads). `SharedPreferencesAsync` reads the platform every
/// time, so a value written by another isolate is never hidden behind a
/// per-isolate cache. Never throws.
abstract final class CallStore {
  static const handledKey = 'call_handled_voip_v1';
  static const pendingAcceptKey = 'call_pending_accept_v1';

  static const _tag = 'CallStore';
  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  // ── Handled VoIP invites (E-4, RN `@vibe_handled_calls`) ───────────────

  /// This VoIP invite was already presented (last
  /// [CallTimings.handledVoipIds] ids, no TTL, like RN).
  static Future<bool> isHandled(String callId) async =>
      (await _handled()).contains(callId);

  static Future<void> markHandled(String callId) async {
    try {
      final list = (await _handled())..remove(callId);
      list.add(callId);
      final kept = list.length > CallTimings.handledVoipIds
          ? list.sublist(list.length - CallTimings.handledVoipIds)
          : list;
      await _prefs.setStringList(handledKey, kept);
    } catch (e) {
      Log.w(_tag, 'markHandled: $e');
    }
  }

  static Future<List<String>> _handled() async {
    try {
      return [...?await _prefs.getStringList(handledKey)];
    } catch (_) {
      return [];
    }
  }

  // ── Pending accept (system UI answered while no UI isolate ran) ────────

  /// Saved by the isolate that saw the accept; [apiDone]: `/UpdateCall`
  /// already sent (iOS native, or that isolate).
  static Future<void> savePendingAccept(
    Map<String, dynamic> payload, {
    bool apiDone = false,
    DateTime? at,
  }) async {
    try {
      await _prefs.setString(
        pendingAcceptKey,
        jsonEncode({
          'payload': payload,
          'at': (at ?? DateTime.now()).millisecondsSinceEpoch,
          'apiDone': apiDone,
        }),
      );
    } catch (e) {
      Log.w(_tag, 'savePendingAccept: $e');
    }
  }

  /// Destructive read: one consumer acts on it. Older than
  /// [CallTimings.coldStartTtl] reads as none.
  static Future<PendingAccept?> takePendingAccept({DateTime? now}) async {
    try {
      final raw = await _prefs.getString(pendingAcceptKey);
      if (raw == null) return null;
      await _prefs.remove(pendingAcceptKey);
      final json = jsonDecode(raw);
      if (json is! Map || json['payload'] is! Map) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(
        (json['at'] as num?)?.toInt() ?? 0,
      );
      if ((now ?? DateTime.now()).difference(at) > CallTimings.coldStartTtl) {
        return null;
      }
      return (
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        at: at,
        apiDone: json['apiDone'] == true,
      );
    } catch (e) {
      Log.w(_tag, 'takePendingAccept: $e');
      return null;
    }
  }

  /// [callId] ended: a replayed accept must not drive a dead call (E-17).
  static Future<void> clearPendingAccept(String callId) async {
    try {
      final raw = await _prefs.getString(pendingAcceptKey);
      if (raw == null || !raw.contains(callId)) return;
      final json = jsonDecode(raw);
      final payload = json is Map ? json['payload'] : null;
      final id = payload is Map
          ? '${payload['callId'] ?? payload['call_id'] ?? ''}'
          : '';
      if (id == callId) await _prefs.remove(pendingAcceptKey);
    } catch (_) {}
  }
}
