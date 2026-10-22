/// Pure rules and formatting of the sign-in screen (RN `LoginScreen.jsx`
/// helpers).
abstract final class LoginFormat {
  /// Matches the backend's default OTP cooldown
  /// (session-auth `throttling.cooldownSeconds`).
  static const resendSeconds = 30;

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// 10 digits starting 6–9: every Indian mobile number.
  static final _mobile = RegExp(r'^[6-9]\d{9}$');

  static bool isValidEmail(String value) => _email.hasMatch(value.trim());

  static bool isValidIndianMobile(String value) => _mobile.hasMatch(value);

  /// "9876543210" → "98765 43210".
  static String formatMobile(String digits) => digits.length > 5
      ? '${digits.substring(0, 5)} ${digits.substring(5)}'
      : digits;

  /// "tester@mail.com" → "te***@mail.com".
  static String maskEmail(String email) {
    final normalized = email.trim().toLowerCase();
    final parts = normalized.split('@');
    if (parts.length != 2) return normalized;
    final user = parts.first, domain = parts.last;
    if (user.isEmpty) return '***@$domain';
    if (user.length <= 2) return '${user[0]}***@$domain';
    return '${user.substring(0, 2)}***@$domain';
  }
}
