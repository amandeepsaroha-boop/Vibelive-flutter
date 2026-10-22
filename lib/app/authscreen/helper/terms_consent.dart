import '../../../core/storage/app_prefs.dart';

/// One-time Terms & Conditions consent after a Google / Apple sign-in
/// (OTP users tick the box before SEND OTP). Stored per terms version, per
/// user and per provider, so it is asked exactly once, and again only when
/// [version] is bumped.
abstract final class TermsConsent {
  /// Bump when the wording changes: everyone is asked again.
  static const version = '1.0';

  static bool needed(String? userId, String provider) =>
      AppPrefs.getString(_key(userId, provider)) != 'true';

  static Future<void> accept(String? userId, String provider) async {
    await AppPrefs.setString(_key(userId, provider), 'true');
    await AppPrefs.setString(_key(userId, ''), 'true');
  }

  static String _key(String? userId, String provider) =>
      'terms_accepted:$version:${userId ?? 'anonymous'}'
      '${provider.isEmpty ? '' : ':${provider.toLowerCase()}'}';
}
