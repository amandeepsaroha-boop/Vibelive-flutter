import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/strapi.dart';
import '../query/query_client.dart';
import '../query/query_persist.dart';
import '../storage/app_prefs.dart';
import '../storage/token_storage.dart';
import '../utils/log.dart';
import 'session_health.dart';

@immutable
class SessionState {
  const SessionState({this.user, this.expert});

  static const empty = SessionState();

  /// Public user (`api::public-user.public-user`).
  final JsonMap? user;

  /// Expert (host) profile of this user, if any.
  final JsonMap? expert;

  bool get isAuthenticated => user != null;
  int? get userId => J.integer(user?['id']);
  String? get userDocumentId => J.str(user?['documentId']);
  bool get isExpert =>
      expert != null &&
      (expert!['id'] != null || expert!['documentId'] != null);
  int? get expertId => J.integer(expert?['id']);

  /// Marked "company account" in admin (`is_company_account`).
  bool get isCompanyAccount {
    final u = user;
    if (u == null) return false;
    return [
      u['is_company_account'],
      u['isCompanyAccount'],
    ].any((v) => v == true || v == 'true');
  }

  String? get expertDocumentId => J.str(expert?['documentId']);

  SessionState copyWith({
    JsonMap? user,
    JsonMap? expert,
    bool clearExpert = false,
  }) => SessionState(
    user: user ?? this.user,
    expert: clearExpert ? null : (expert ?? this.expert),
  );
}

/// Logged-in user state (port of the RN auth store's session part).
/// Feature APIs take ids as parameters; screens read them from here.
class SessionStore extends ValueNotifier<SessionState> {
  SessionStore._() : super(SessionState.empty) {
    addListener(() => _signedIn.value = value.isAuthenticated);
  }
  static final SessionStore instance = SessionStore._();

  final _signedIn = ValueNotifier(false);

  /// Flips only on sign-in / sign-out (profile edits don't notify), so the
  /// router's auth guard re-runs exactly when it matters.
  ValueListenable<bool> get signedIn => _signedIn;

  static const _userKey = 'session_user';
  static const _expertKey = 'session_expert';

  /// iOS protected data (keychain, prefs) readable right now; null when
  /// unknown. Installed by the call layer before [restore]: a VoIP push can
  /// boot the app on a locked phone, where both stores read as empty.
  static Future<bool?> Function()? protectedDataAvailable;

  /// Runs before a sign-out drops the token (the call layer ends a live
  /// call: its `/call/Callend` needs the user's token). Bounded.
  static Future<void> Function()? beforeSignOut;

  /// Restores the last session (before `runApp`) and starts
  /// [SessionHealth]. A failed token refresh NEVER signs the user out (only
  /// the Logout button does): it shows "Server unreachable" with Retry.
  /// Never wipes what it could not read (locked VoIP boot): it keeps it for
  /// the next restore.
  Future<void> restore() async {
    SessionHealth.instance.start();
    final locked = await _protectedDataAvailable() == false;
    final user = _readJson(_userKey);
    if (user == null) {
      // Prefs read before the first unlock look empty: keep the tokens.
      if (locked) return;
      // A crash mid-login can leave tokens without a user: never send them.
      await TokenStorage.instance.clear();
      return;
    }
    final hasToken = await TokenStorage.instance.hasTokens();
    if (hasToken == false) {
      if (!locked) await _wipe();
      return;
    }
    // Stored, or unreadable right now (unknown: keep).
    value = SessionState(user: user, expert: _readJson(_expertKey));
  }

  static Future<bool?> _protectedDataAvailable() async {
    try {
      return await protectedDataAvailable?.call();
    } catch (_) {
      return null;
    }
  }

  Future<void> signIn({
    required JsonMap user,
    required String accessToken,
    String? refreshToken,
    JsonMap? expert,
  }) async {
    await TokenStorage.instance.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    ApiClient.resetLogoutFlag();
    value = SessionState(user: user, expert: expert);
    await _persist();
  }

  Future<void> updateUser(JsonMap user) async {
    value = value.copyWith(user: {...?value.user, ...user});
    await _persist();
  }

  Future<void> updateExpert(JsonMap? expert) async {
    value = expert == null
        ? value.copyWith(clearExpert: true)
        : value.copyWith(expert: expert);
    await _persist();
  }

  /// Local sign-out: tokens, cached queries, persisted data. The logout API
  /// call (if any) is the auth feature's job and happens before this.
  Future<void> signOut() async {
    final hook = beforeSignOut;
    if (hook != null && value.isAuthenticated) {
      try {
        await hook().timeout(const Duration(seconds: 6));
      } catch (e) {
        Log.w('SessionStore', 'before sign-out: $e');
      }
    }
    ApiClient.beginLogout();
    value = SessionState.empty;
    queryCache.clear();
    await _wipe();
    Log.d('SessionStore', 'signed out');
  }

  Future<void> _wipe() async {
    await TokenStorage.instance.clear();
    await AppPrefs.remove(_userKey);
    await AppPrefs.remove(_expertKey);
    try {
      await QueryPersist.clearAll();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final s = value;
    if (s.user != null) {
      await AppPrefs.setString(_userKey, jsonEncode(s.user));
    }
    if (s.expert != null) {
      await AppPrefs.setString(_expertKey, jsonEncode(s.expert));
    } else {
      await AppPrefs.remove(_expertKey);
    }
  }

  static JsonMap? _readJson(String key) {
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
