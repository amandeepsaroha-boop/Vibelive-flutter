import 'package:flutter/foundation.dart';

import '../network/strapi.dart';
import '../session/session_store.dart';
import 'analytics.dart';

/// Keeps who the user is in step with the session, on both platforms:
/// user id, Firebase user properties (role, host state…), Meta advanced
/// matching, and a `logout` event when the session ends (RN `setAuth` /
/// `clearAuth` analytics).
abstract final class AnalyticsIdentity {
  static String? _userKey;
  static String? _signature;
  static bool _attached = false;

  /// Why the next sign-out happens; anything else is an expired session.
  static String? _signOutReason;

  /// Before `runApp`, after the session is restored.
  static void attach() {
    if (_attached) return;
    _attached = true;
    SessionStore.instance.addListener(_sync);
    _sync();
  }

  /// Why the next sign-out happens (`user`, `terms_declined`,
  /// `account_deleted`…). A more specific reason set first is kept: the
  /// generic `logout()` marks `user` without replacing it.
  static void markSignOut(String reason, {bool keep = false}) {
    if (keep && _signOutReason != null) return;
    _signOutReason = reason;
  }

  static void _sync() {
    final s = SessionStore.instance.value;
    final key = s.userDocumentId ?? s.userId?.toString();
    if (key == null) {
      final was = _userKey;
      _userKey = null;
      _signature = null;
      if (was != null) {
        Analytics.log('logout', {
          'reason': _signOutReason ?? 'session_expired',
        });
        _signOutReason = null;
        Analytics.setUser(null);
        Analytics.userProperty('user_role', null);
        Analytics.userProperty('host_approved', null);
      }
      return;
    }
    final user = s.user ?? const {};
    final expert = s.expert;
    final role = s.isExpert ? 'host' : 'client';
    final approved = expert == null ? null : J.boolean(expert['isApproved']);
    final signature = [
      key,
      role,
      approved,
      J.str(user['name']),
      J.str(user['email']),
      J.str(user['mobile']),
      J.str(user['gender']),
      J.str(user['date_of_birth']),
    ].join('|');
    if (signature == _signature) return;
    _signature = signature;
    _userKey = key;
    _signOutReason = null;

    Analytics.setUser(key, data: userData(user));
    Analytics.userProperty('user_role', role);
    Analytics.userProperty(
      'host_approved',
      approved == null ? null : (approved ? 'true' : 'false'),
    );
    Analytics.userProperty(
      'is_company',
      J.boolean(user['is_company_account']) ? 'true' : 'false',
    );
    final gender = J.str(user['gender'])?.toLowerCase();
    if (gender != null) Analytics.userProperty('gender', gender);
  }

  /// Meta advanced-matching fields from a public-user.
  @visibleForTesting
  static AnalyticsUserData userData(JsonMap user) {
    final digits = (J.str(user['mobile']) ?? '').replaceAll(RegExp(r'\D'), '');
    final phone = digits.isEmpty
        ? null
        : (digits.length == 10 ? '91$digits' : digits);
    final name = J.str(user['name'])?.trim();
    final gender = J.str(user['gender'])?.toLowerCase();
    final dob = J.str(user['date_of_birth']);
    final dobDigits = dob == null
        ? null
        : RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(dob);
    return AnalyticsUserData(
      email: J.str(user['email']),
      phone: phone,
      firstName: name == null || name.isEmpty ? null : name.split(' ').first,
      gender: gender == null
          ? null
          : (gender.startsWith('f') ? 'f' : (gender.startsWith('m') ? 'm' : null)),
      dateOfBirth: dobDigits == null
          ? null
          : '${dobDigits[1]}${dobDigits[2]}${dobDigits[3]}',
    );
  }

  @visibleForTesting
  static void debugReset() {
    SessionStore.instance.removeListener(_sync);
    _attached = false;
    _userKey = null;
    _signature = null;
    _signOutReason = null;
  }
}
