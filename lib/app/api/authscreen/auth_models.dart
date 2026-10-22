import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import 'auth_errors.dart';

enum OtpChannel {
  sms,
  email;

  /// Trimmed, and emails lower-cased, as the RN login screen sent them.
  String normalize(String identifier) => this == OtpChannel.email
      ? identifier.trim().toLowerCase()
      : identifier.trim();
}

/// Providers `/session-auth/social/exchange` accepts.
enum SocialProvider { google, apple, facebook }

class OtpRequestInput {
  const OtpRequestInput({
    required this.identifier,
    this.channel = OtpChannel.sms,
  });

  /// Mobile number or email.
  final String identifier;
  final OtpChannel channel;
}

class OtpVerifyInput {
  const OtpVerifyInput({
    required this.identifier,
    required this.code,
    this.channel = OtpChannel.sms,
    this.referrerCode,
    this.fcmToken,
    this.voipToken,
  });

  final String identifier;
  final String code;
  final OtpChannel channel;

  /// Referral code with its `-R`/`-I` intent suffix re-attached.
  final String? referrerCode;

  /// This install's push tokens, so calls can reach it right after login.
  final String? fcmToken;
  final String? voipToken;
}

class SocialLoginInput {
  const SocialLoginInput({
    required this.provider,
    required this.idToken,
    this.referrerCode,
    this.fcmToken,
    this.voipToken,
  });

  final SocialProvider provider;

  /// Firebase ID token from the provider sign-in.
  final String idToken;
  final String? referrerCode;
  final String? fcmToken;
  final String? voipToken;
}

class LogoutInput {
  const LogoutInput({this.fcmToken, this.voipToken});

  /// This install's push tokens, unregistered so the device stops getting
  /// the user's pushes.
  final String? fcmToken;
  final String? voipToken;
}

/// Answer of `/session-auth/otp/verify` and `/session-auth/social/exchange`
/// (RN `normalizeAuthResponse`).
class LoginResult {
  const LoginResult({
    required this.raw,
    required this.accessToken,
    this.refreshToken,
    this.user,
    this.session,
    this.expert,
  });

  /// Null when the body carries no access token.
  static LoginResult? fromResponse(dynamic body) {
    if (body is! Map) return null;
    final hasTokens = body['accessToken'] != null || body['token'] != null;
    final d = Map<String, dynamic>.from(
      !hasTokens && body['data'] is Map ? body['data'] as Map : body,
    );
    final tokens = _map(d['tokens']);
    final session = _map(d['session']);
    final access =
        J.str(d['accessToken']) ??
        J.str(d['token']) ??
        J.str(tokens?['accessToken']);
    if (access == null) return null;
    return LoginResult(
      raw: d,
      accessToken: access,
      refreshToken:
          J.str(d['refreshToken']) ??
          J.str(session?['refreshToken']) ??
          J.str(tokens?['refreshToken']),
      user: Strapi.map(d['user']) ?? Strapi.map(session?['user']),
      session: session,
    );
  }

  /// `/session-auth/otp/request` signs whitelisted / test numbers in itself
  /// (`bypassed: true` with tokens): no code is sent. Null otherwise.
  static LoginResult? fromBypass(Object? body) =>
      body is Map && J.boolean(body['bypassed']) ? fromResponse(body) : null;

  final JsonMap raw;
  final String accessToken;
  final String? refreshToken;

  /// Public-user. After sign-in: merged with the profile read and normalized.
  final JsonMap? user;

  /// `{id, documentId, deviceId, appKey, expiresAt}`.
  final JsonMap? session;

  /// Expert profile, when the sign-in profile loader returned one.
  final JsonMap? expert;

  /// Social sign-up without a verified mobile: the app must ask for it.
  bool get requiresPhoneVerification =>
      J.boolean(raw['requiresPhoneVerification']);

  /// RN analytics rule: an account without a name never finished sign-up.
  bool get isNewUser => J.str(user?['name']) == null;

  LoginResult copyWith({JsonMap? user, JsonMap? expert}) => LoginResult(
    raw: raw,
    accessToken: accessToken,
    refreshToken: refreshToken,
    user: user ?? this.user,
    session: session,
    expert: expert ?? this.expert,
  );

  static JsonMap? _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;
}

/// Public-user as kept in the session (RN `toStoredUser`): both spellings of
/// the company flag, set from any of the three the backend uses.
abstract final class AuthUser {
  static JsonMap normalize(JsonMap user) {
    bool flag(String key) => user[key]?.toString() == 'true';
    final isCompany =
        flag('is_company_account') ||
        flag('isCompanyAccount') ||
        flag('is_company');
    return {
      ...user,
      'is_company_account': isCompany,
      'isCompanyAccount': isCompany,
    };
  }
}

/// `/user-referrals` lookup for the code typed on the login screen.
class ReferralCheck {
  const ReferralCheck({required this.isValid, this.referrerName, this.raw});

  factory ReferralCheck.fromResponse(dynamic body) {
    final rows = Strapi.list(body is Map ? body['data'] : null);
    if (rows.isEmpty) return const ReferralCheck(isValid: false);
    final user = Strapi.map(rows.first['user']);
    return ReferralCheck(
      isValid: true,
      referrerName: J.str(user?['name']),
      raw: rows.first,
    );
  }

  final bool isValid;

  /// For "Invited by …"; null when the referrer has no name yet.
  final String? referrerName;
  final JsonMap? raw;
}

/// Who a referral / install-referrer code belongs to: the host to open after
/// login when the owner is an expert.
class ReferrerTarget {
  const ReferrerTarget({
    required this.handler,
    required this.isExpert,
    this.documentId,
  });

  /// Null when no referral has this code.
  static ReferrerTarget? fromResponse(dynamic body, {required String handler}) {
    final rows = Strapi.list(body is Map ? body['data'] : null);
    if (rows.isEmpty) return null;
    final user = Strapi.map(rows.first['user']);
    final expert = Strapi.map(user?['expert']);
    final isExpert =
        expert != null &&
        (J.str(expert['documentId']) != null || J.str(expert['id']) != null);
    return ReferrerTarget(
      handler: handler,
      isExpert: isExpert,
      documentId: J.str(expert?['documentId']) ?? J.str(user?['documentId']),
    );
  }

  final String handler;
  final bool isExpert;

  /// Expert documentId, else the referring user's.
  final String? documentId;
}

/// Server verdict on the 18+ requirement.
enum AgeGateStatus {
  ok,
  required,
  blocked,

  /// Not determined yet. Never gates: "could not find out" is not "needs a
  /// date", and a network blip must not lock anyone out.
  unknown;

  bool get gates =>
      this == AgeGateStatus.required || this == AgeGateStatus.blocked;
}

abstract final class AgeGate {
  /// Public-user fields that carry the verdict. `ageGateStatus` comes from
  /// GET /me only and wins over the others.
  static const fields = [
    'date_of_birth',
    'age_verified_at',
    'age_blocked',
    'ageGateStatus',
  ];

  /// Verdict for a user payload (RN `resolveAgeGateStatus`).
  /// `date_of_birth: null` means "not entered yet"; a payload without the key
  /// predates the age gate and is `unknown` until GET /me confirms it.
  static AgeGateStatus resolve(Object? user) {
    if (user is! Map) return AgeGateStatus.unknown;
    final verdict = user['ageGateStatus']?.toString().toLowerCase();
    for (final status in const [
      AgeGateStatus.ok,
      AgeGateStatus.required,
      AgeGateStatus.blocked,
    ]) {
      if (status.name == verdict) return status;
    }
    if (_isTrue(user['age_blocked'])) return AgeGateStatus.blocked;
    if (_hasValue(user['date_of_birth']) ||
        _hasValue(user['age_verified_at'])) {
      return AgeGateStatus.ok;
    }
    if (user.containsKey('date_of_birth')) return AgeGateStatus.required;
    return AgeGateStatus.unknown;
  }

  /// The verdict fields present on [user], to merge into the session user.
  static JsonMap fieldsOf(JsonMap user) => {
    for (final key in fields)
      if (user.containsKey(key)) key: user[key],
  };

  static bool _isTrue(Object? v) =>
      v == true || v == 1 || v?.toString().toLowerCase() == 'true';

  static bool _hasValue(Object? v) =>
      v != null && v.toString().trim().isNotEmpty;
}

/// Date of birth as typed → ISO date for PUT /me/date-of-birth (RN
/// `validateDateOfBirth`). Format and calendar checks only: whether the
/// person is 18+ is the server's call.
class DateOfBirthCheck {
  const DateOfBirthCheck._({this.isoDate, this.errorKey});

  factory DateOfBirthCheck.validate({
    required String day,
    required String month,
    required String year,
    DateTime? now,
  }) {
    final d = day.trim();
    final m = month.trim();
    final y = year.trim();
    if (d.isEmpty || m.isEmpty || y.length != 4) {
      return const DateOfBirthCheck._(errorKey: AuthErrorKeys.dobIncomplete);
    }
    const invalid = DateOfBirthCheck._(errorKey: AuthErrorKeys.dobInvalid);
    final dd = int.tryParse(d);
    final mm = int.tryParse(m);
    final yy = int.tryParse(y);
    if (dd == null || mm == null || yy == null) return invalid;

    // Round-trip through a date to reject 31/02, 00/13 and the like.
    final date = DateTime.utc(yy, mm, dd);
    final isRealDate = date.year == yy && date.month == mm && date.day == dd;
    if (!isRealDate || yy < _oldestYear) return invalid;
    if (date.isAfter(now ?? DateTime.now())) {
      return const DateOfBirthCheck._(errorKey: AuthErrorKeys.dobFuture);
    }
    String pad(int v, int width) => v.toString().padLeft(width, '0');
    return DateOfBirthCheck._(
      isoDate: '${pad(yy, 4)}-${pad(mm, 2)}-${pad(dd, 2)}',
    );
  }

  /// From a date picker.
  factory DateOfBirthCheck.fromDate(DateTime date, {DateTime? now}) =>
      DateOfBirthCheck.validate(
        day: '${date.day}',
        month: '${date.month}',
        year: '${date.year}',
        now: now,
      );

  static const _oldestYear = 1900;

  /// `YYYY-MM-DD`, when valid.
  final String? isoDate;

  /// i18n key of the problem, when invalid.
  final String? errorKey;

  bool get isValid => isoDate != null;
}

/// Where a signed-in user belongs after login or a cold start: age gate,
/// then the language question, then the app.
enum OnboardingStep { signedOut, ageGate, language, home }

extension AuthSessionState on SessionState {
  /// The 18+ verdict for the signed-in user.
  AgeGateStatus get ageGateStatus => AgeGate.resolve(user);

  /// documentId, else id (RN `userKeyOf`): scopes per-user cache entries.
  String? get userKey => userDocumentId ?? J.str(user?['id']);
}
