import '../../../core/network/api_client.dart';
import 'auth_models.dart';

/// Who is behind a referral code (`/user-referrals`): the login screen's
/// "Invited by …" check and the install-referrer target. Codes are
/// upper-case.
abstract final class ReferrerApi {
  /// Sent without a token, like RN (`_skipAuthToken`): it runs before login.
  static Future<ReferralCheck> validateCode(String code) async {
    final normalized = normalizeCode(code);
    if (normalized.isEmpty) return const ReferralCheck(isValid: false);
    final body = await ApiClient.get(
      '/user-referrals',
      query: {
        'filters[referralCode][\$eq]': normalized,
        'populate[user]': 'true',
      },
      skipAuth: true,
    );
    return ReferralCheck.fromResponse(body);
  }

  /// Null when no referral has this code.
  static Future<ReferrerTarget?> resolveTarget(String handler) async {
    final code = normalizeCode(handler);
    if (code.isEmpty) return null;
    final body = await ApiClient.get(
      '/user-referrals',
      query: {
        'filters[referralCode][\$eq]': code,
        'populate[user][populate][expert]': 'true',
      },
    );
    return ReferrerTarget.fromResponse(body, handler: handler.trim());
  }

  static String normalizeCode(String code) => code.trim().toUpperCase();
}
