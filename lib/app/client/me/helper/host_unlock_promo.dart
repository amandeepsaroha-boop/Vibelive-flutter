import '../../../../core/storage/app_prefs.dart';

/// The one-time "feature unlocked" celebration on "Become a Host" (RN
/// `useHostUnlockPromo`): shown once per account, the first time a client's
/// Personal Info is complete. Another account on the same phone gets its own.
abstract final class HostUnlockPromo {
  // Same key as RN, so a user who already saw it there never sees it again.
  static const _prefix = '@has_seen_become_host_unlock_1';

  static String _key(String userKey) => '$_prefix:$userKey';

  static bool seen(String userKey) =>
      userKey.isEmpty || AppPrefs.getString(_key(userKey)) != null;

  static Future<void> markSeen(String userKey) async {
    if (userKey.isEmpty) return;
    await AppPrefs.setString(_key(userKey), 'true');
  }
}
