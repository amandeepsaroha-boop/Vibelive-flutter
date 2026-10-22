import 'package:flutter/foundation.dart';

/// Digits in a sign-in code (RN `OTP_LENGTH`).
const otpLength = 4;

/// Android OTP auto-read for mobile sign-in (RN `utils/smsOtpAutofill.js`
/// over the in-house `VibeSmsOtp` module: SMS Retriever for the code, Phone
/// Number Hint for the number).
///
/// iOS needs none of this: the code field's `AutofillHints.oneTimeCode` makes
/// the keyboard offer the code, and the mobile field's
/// `AutofillHints.telephoneNumber` the user's own number.
///
/// The retriever only hands over an SMS that ends with the app hash, which
/// the backend appends from session-auth `otp.msg91.autofillCode`.
///
/// Every call is best effort and never throws. [instance] is a no-op until
/// the native side exists; set it at startup to the real implementation.
abstract class SmsOtpAutofill {
  const SmsOtpAutofill();

  static SmsOtpAutofill instance = const NoSmsOtpAutofill();

  /// False on iOS and on builds without the native module.
  bool get isSupported;

  /// Calls [onCode] once with the code of the next verification SMS. Start
  /// it BEFORE requesting the code: the retriever only sees messages that
  /// arrive after it is armed (for 5 minutes). Returns stop(), safe to call
  /// more than once.
  VoidCallback listen(ValueChanged<String> onCode);

  /// System picker with the SIM numbers: a 10-digit number, or null when
  /// unavailable or dismissed.
  Future<String?> requestPhoneHint();

  /// Hash(es) the OTP SMS must end with for this build's signing key.
  Future<List<String>> appHashes();

  /// First standalone [digits]-digit group of [message]:
  /// "Your OTP is 4821 … h4Sk9…" → "4821".
  static String? extractOtp(String? message, {int digits = otpLength}) =>
      RegExp('(?:^|\\D)(\\d{$digits})(?!\\d)').firstMatch(message ?? '')?[1];
}

/// No native module yet: the user types the code (or iOS offers it).
class NoSmsOtpAutofill extends SmsOtpAutofill {
  const NoSmsOtpAutofill();

  @override
  bool get isSupported => false;

  @override
  VoidCallback listen(ValueChanged<String> onCode) => _noop;

  @override
  Future<String?> requestPhoneHint() async => null;

  @override
  Future<List<String>> appHashes() async => const [];

  static void _noop() {}
}
