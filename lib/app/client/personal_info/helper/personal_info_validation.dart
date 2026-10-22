import '../../../api/client/client_models.dart';
import '../../../api/hosthub/eligibility.dart';

/// First problem of the form, in RN's order (one alert at a time).
enum PersonalInfoIssue {
  name('name_required'),
  emailMissing('email_required'),
  emailInvalid('email_invalid'),
  mobileMissing('mobile_required'),
  mobileInvalid('mobile_invalid'),
  state('state_required'),
  district('district_required');

  const PersonalInfoIssue(this._key);
  final String _key;

  /// i18n key of the alert message.
  String get messageKey => 'client:personal_info.errors.$_key';
}

/// RN `handleSave` checks. Name, valid email and a 10-digit mobile are what
/// calls and "Become a Host" need; state and district complete the profile.
abstract final class PersonalInfoValidation {
  static PersonalInfoIssue? validate({
    required String name,
    required String email,
    required String mobile,
    required GeoOption? state,
    required GeoOption? district,
  }) {
    final mail = email.trim();
    if (name.trim().length < 2) return PersonalInfoIssue.name;
    if (mail.isEmpty) return PersonalInfoIssue.emailMissing;
    if (!HostEligibility.emailPattern.hasMatch(mail)) {
      return PersonalInfoIssue.emailInvalid;
    }
    if (mobile.trim().isEmpty) return PersonalInfoIssue.mobileMissing;
    if (!RegExp(r'^\d{10}$').hasMatch(digits(mobile))) {
      return PersonalInfoIssue.mobileInvalid;
    }
    if ((state?.name ?? '').isEmpty) return PersonalInfoIssue.state;
    if ((district?.name ?? '').isEmpty) return PersonalInfoIssue.district;
    return null;
  }

  static String digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Avatar letter: first Latin letter of the name, else "U" (RN
  /// `initialLetter`).
  static String initialOf(String name) =>
      RegExp('[A-Za-z]').firstMatch(name.trim())?.group(0)?.toUpperCase() ??
      'U';
}
