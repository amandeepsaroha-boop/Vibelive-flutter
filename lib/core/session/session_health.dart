import 'dart:async';

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../query/query_client.dart';
import '../utils/log.dart';
import 'session_store.dart';

/// Why the signed-in session could not be refreshed.
enum SessionIssue {
  /// No usable answer: no connection, a timeout, a server error, a reply
  /// that could not be read. The server's problem, not the user's.
  unreachable,

  /// The server answered and refused the refresh token. Can still be the
  /// server's doing (a refresh it completed after the app had given up
  /// rotates the token the app never received), so this is offered to the
  /// user, never acted on.
  rejected,
}

/// The app never signs anyone out on its own: only the Logout button does.
/// When the session can't be refreshed, the user stays signed in (tokens
/// and data kept) and this says why, for the "Server unreachable" screen
/// with Retry ([SessionIssueHost]). Clears itself on the next successful
/// refresh and on sign-out. Null: all is well.
class SessionHealth extends ValueNotifier<SessionIssue?> {
  SessionHealth._() : super(null);

  static final instance = SessionHealth._();

  StreamSubscription<ApiException>? _trouble;
  StreamSubscription<String>? _refreshed;

  /// Listens to the API client; idempotent (called by
  /// [SessionStore.restore]).
  void start() {
    _trouble ??= ApiClient.onSessionExpired.listen(report);
    _refreshed ??= ApiClient.onTokenRefreshed.listen((_) => value = null);
    SessionStore.instance
      ..removeListener(_onSession)
      ..addListener(_onSession);
  }

  void _onSession() {
    if (!SessionStore.instance.value.isAuthenticated) value = null;
  }

  /// A refresh that failed with [e]. Only while signed in.
  @visibleForTesting
  void report(ApiException e) {
    if (!SessionStore.instance.value.isAuthenticated) return;
    final refused =
        e.statusCode == 401 ||
        e.statusCode == 403 ||
        e.type == ApiErrorType.unauthorized;
    value = refused ? SessionIssue.rejected : SessionIssue.unreachable;
    Log.w('SessionHealth', 'session refresh failed (${value!.name}): $e');
  }

  bool _retrying = false;

  /// Retry: refresh the session now. On success the issue clears and every
  /// screen loads again; on failure it stays (its kind may change). True on
  /// success.
  Future<bool> retry() async {
    if (_retrying) return false;
    _retrying = true;
    try {
      await ApiClient.refreshSession();
      value = null;
      queryCache.invalidateQueries(const []);
      return true;
    } catch (e) {
      report(ApiException.from(e));
      return false;
    } finally {
      _retrying = false;
    }
  }

  @visibleForTesting
  void debugReset() {
    value = null;
    _retrying = false;
  }
}
