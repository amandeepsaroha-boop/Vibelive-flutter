import 'dart:convert';

import '../../../../core/storage/app_prefs.dart';
import 'push_envelope.dart';

/// First-line push dedupe (RN `processed_message_ids`): the same FCM message
/// delivered twice (redelivery after a kill, two listeners) is handled once,
/// and a push FCM held for more than a day is not drawn at all.
///
/// Calls have their own per-call dedupe in the call logic; this only
/// recognises the same message id.
abstract final class PushDedupe {
  static const maxTracked = 200;
  static const maxAge = Duration(hours: 24);
  static const storageKey = 'push_processed_message_ids';

  /// True when [m]'s message id was already seen; marks it seen otherwise.
  /// Messages without an id are never dropped here.
  static Future<bool> isDuplicate(PushEnvelope m) async {
    final id = m.messageId;
    if (id == null || id.isEmpty) return false;
    final seen = _read();
    if (seen.contains(id)) return true;
    seen.add(id);
    if (seen.length > maxTracked) seen.removeRange(0, seen.length - maxTracked);
    await AppPrefs.setString(storageKey, jsonEncode(seen));
    return false;
  }

  /// Older than a day: not worth drawing (unknown send time = fresh).
  static bool isTooOld(PushEnvelope m, {DateTime? now}) {
    final sent = m.sentAt;
    return sent != null && (now ?? DateTime.now()).difference(sent) > maxAge;
  }

  static List<String> _read() {
    final raw = AppPrefs.getString(storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      return list is List ? [for (final e in list) '$e'] : [];
    } on FormatException {
      return [];
    }
  }
}
