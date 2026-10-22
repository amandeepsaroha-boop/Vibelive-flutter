import '../../../core/network/strapi.dart';
import 'profile_models.dart';
import 'verification_models.dart';

enum PersonalInfoField {
  fullName('full_name'),
  email('email'),
  mobile('mobile'),
  state('state'),
  district('district');

  const PersonalInfoField(this._key);
  final String _key;

  String get i18nKey => 'hosthub:personal_fields.$_key';
}

/// Gates of the host onboarding flow, in order (RN `hostEligibility.js`,
/// `badgeApplication.js`):
///   1. Personal Info complete → may become a host (Professional Details).
///   2. Host profile complete  → may request approval.
///   3. Host profile approved  → may apply for the Verification Badge.
/// Works on raw maps so the session's user/expert can be passed directly.
abstract final class HostEligibility {
  static final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  /// Shown when the badge flow is opened before approval.
  static const approvalRequiredKey = 'hosthub:badge.approval_required';

  /// Personal Info fields still missing. State/district count when either
  /// the relation is populated or the `address_JSON` copy exists, since the
  /// session user is fetched without relations.
  static List<PersonalInfoField> missingPersonalInfo(JsonMap? rawUser) {
    final user = Strapi.map(rawUser) ?? const {};
    final address = user['address_JSON'] is Map
        ? user['address_JSON'] as Map
        : const {};
    String text(dynamic v) => (J.str(v) ?? '').trim();
    return [
      if (text(user['name']).isEmpty) PersonalInfoField.fullName,
      if (!emailPattern.hasMatch(text(user['email']))) PersonalInfoField.email,
      if (text(user['mobile']).replaceAll(RegExp(r'\D'), '').length < 10)
        PersonalInfoField.mobile,
      if (_relationName(user['state']).isEmpty &&
          text(address['state']).isEmpty)
        PersonalInfoField.state,
      if (_relationName(user['district']).isEmpty &&
          text(address['district']).isEmpty)
        PersonalInfoField.district,
    ];
  }

  static bool isPersonalInfoComplete(JsonMap? user) =>
      missingPersonalInfo(user).isEmpty;

  /// True once an admin approved the host profile.
  static bool isHostApproved(JsonMap? expert) =>
      HostFlag.isOn(Strapi.map(expert)?['isApproved']);

  /// True when the Verification Badge is already granted.
  static bool isHostVerified(JsonMap? expert) =>
      HostFlag.isOn(Strapi.map(expert)?['isVerified']);

  /// The badge flow is open to approved hosts and to badge holders.
  static bool canApplyForBadge(JsonMap? expert) =>
      isHostApproved(expert) || isHostVerified(expert);

  /// Badge progress read from the profile's populated
  /// `expert_verifications` (no extra request). Null for a non-host or a
  /// host not approved yet. With several rows the furthest counts, so an old
  /// abandoned row never nags a host who has since applied.
  static VerificationStep? badgeStep(JsonMap? expert) {
    final e = Strapi.map(expert);
    if (e == null || (e['id'] == null && e['documentId'] == null)) return null;
    if (isHostVerified(e)) return VerificationStep.success;
    if (!isHostApproved(e)) return null;
    var best = VerificationStep.fee;
    for (final row in Strapi.list(e['expert_verifications'])) {
      final step = VerificationRecord.nextStepOf(row);
      if (step.index > best.index) best = step;
    }
    return best;
  }

  /// i18n key of the badge prompt pill, or null when nothing is left to do.
  static String? badgePromptKey(JsonMap? expert) => switch (badgeStep(expert)) {
    VerificationStep.fee => 'hosthub:badge.apply',
    VerificationStep.form => 'hosthub:badge.finish',
    _ => null,
  };

  static String _relationName(dynamic relation) {
    var node = Strapi.node(relation);
    if (node is List) node = node.isEmpty ? null : node.first;
    final m = Strapi.map(node);
    if (m == null) return '';
    return (J.str(m['name']) ??
            J.str(m['stateNames']) ??
            J.str(m['districtNames']) ??
            J.str(m['cityNames']) ??
            '')
        .trim();
  }
}
