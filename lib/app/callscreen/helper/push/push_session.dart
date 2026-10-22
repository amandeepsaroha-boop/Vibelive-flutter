import 'dart:convert';

import '../../../../core/network/strapi.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/storage/app_prefs.dart';

/// Who is signed in, readable from any isolate. The UI isolate has a restored
/// [SessionStore]; a background isolate (FCM, CallKit) only has the prefs
/// `SessionStore` persisted, so this reads those (keys owned by
/// `SessionStore`: `session_user`, `session_expert`).
abstract final class PushSession {
  static const _userKey = 'session_user';
  static const _expertKey = 'session_expert';

  static SessionState get _live => SessionStore.instance.value;

  static bool get isSignedIn =>
      _live.isAuthenticated || _stored(_userKey) != null;

  /// Numeric public-user id (string).
  static String? get userId =>
      J.str(_live.userId) ?? J.str(_stored(_userKey)?['id']);

  static bool get isExpert {
    if (_live.isAuthenticated) return _live.isExpert;
    final expert = _stored(_expertKey);
    return expert != null &&
        (expert['id'] != null || expert['documentId'] != null);
  }

  static Map<String, dynamic>? _stored(String key) {
    final raw = AppPrefs.getString(key);
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
