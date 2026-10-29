import '../analytics.dart';

/// Sign-in and onboarding events (Firebase + Meta). Catalog:
/// docs/analytics_events.md.
///
/// `method` is always one of `phone`, `email`, `google`, `apple`.
abstract final class AuthEvents {
  // ── Sign-in options ────────────────────────────────────────────────────

  /// A sign-in way was chosen: the mobile / email sheet opened, or a
  /// Google / Apple button was tapped. [source]: `options` (the options
  /// page), `switch` (the "use email / mobile" link inside the sheet),
  /// `phone_required` (a social user sent to the mobile sheet).
  static void methodSelected(String method, {String source = 'options'}) =>
      Analytics.log('login_method_selected', {
        'method': method,
        'source': source,
      });

  /// The mobile / email sheet was closed without signing in.
  static void sheetClosed({required String method, required bool otpSent}) =>
      Analytics.log('login_sheet_closed', {
        'method': method,
        'otp_sent': otpSent,
      });

  /// SEND OTP / Verify refused locally: [field] is `phone`, `email` or
  /// `code`.
  static void inputInvalid({required String method, required String field}) =>
      Analytics.log('login_input_invalid', {'method': method, 'field': field});

  /// SEND OTP tapped with the terms box unticked.
  static void termsRequired({required String method}) =>
      Analytics.log('login_terms_required', {'method': method});

  /// The terms checkbox of the mobile / email form.
  static void termsToggled({required bool accepted}) =>
      Analytics.log('login_terms_toggled', {'accepted': accepted});

  /// Android SIM-number picker answered.
  static void phoneHint({required bool picked}) =>
      Analytics.log('phone_hint_result', {'picked': picked});

  /// Terms / privacy / guidelines opened. [doc]: `terms`, `privacy`,
  /// `guidelines`; [source]: `login_options`, `login_form`, `terms_page`.
  static void legalOpened({required String doc, required String source}) =>
      Analytics.log('legal_link_opened', {'doc': doc, 'source': source});

  // ── OTP ────────────────────────────────────────────────────────────────

  /// A code was sent ([cooldownResume]: still valid from a moment ago, the
  /// code step came back without a new SMS).
  static void otpRequested({
    required String method,
    bool cooldownResume = false,
  }) => Analytics.log('otp_requested', {
    'method': method,
    if (cooldownResume) 'cooldown_resume': true,
  });

  static void otpRequestFailed({
    required String method,
    required String error,
  }) =>
      Analytics.log('otp_request_failed', {'method': method, 'error': error});

  static void otpResent({required String method}) =>
      Analytics.log('otp_resent', {'method': method});

  static void otpResendFailed({required String method, required String error}) =>
      Analytics.log('otp_resend_failed', {'method': method, 'error': error});

  /// The whole code arrived at once. [source]: `sms_retriever` (Android
  /// auto-read) or `keyboard` (iOS suggestion / paste).
  static void otpAutofilled({required String method, required String source}) =>
      Analytics.log('otp_autofilled', {'method': method, 'source': source});

  static void otpVerifyFailed({required String method, required String error}) =>
      Analytics.log('otp_verify_failed', {'method': method, 'error': error});

  /// "Change" on the code step: back to the number / email.
  static void otpChangeIdentifier({required String method}) =>
      Analytics.log('otp_change_identifier', {'method': method});

  // ── Google / Apple ─────────────────────────────────────────────────────

  static void socialStarted(String provider) =>
      Analytics.log('social_login_started', {'provider': provider});

  /// The provider's sheet was closed without an account.
  static void socialCancelled(String provider) =>
      Analytics.log('social_login_cancelled', {'provider': provider});

  /// [stage]: `provider` (Google / Apple failed) or `server` (our backend
  /// refused the token).
  static void socialFailed(
    String provider, {
    required String error,
    required String stage,
  }) => Analytics.log('social_login_failed', {
    'provider': provider,
    'error': error,
    'stage': stage,
  });

  /// The backend wants a verified mobile from this social user.
  static void socialPhoneRequired(String provider) =>
      Analytics.log('social_phone_required', {'provider': provider});

  // ── Terms consent (social sign-in) ─────────────────────────────────────

  static void termsConsentShown(String provider) =>
      Analytics.log('terms_consent_shown', {'provider': provider});

  static void termsConsentAccepted(String provider) =>
      Analytics.log('terms_consent_accepted', {'provider': provider});

  static void termsConsentDeclined(String provider) =>
      Analytics.log('terms_consent_declined', {'provider': provider});

  // ── Referral code on the login screen ──────────────────────────────────

  /// "Have a referral code?" opened the field.
  static void referralFieldOpened() =>
      Analytics.log('referral_code_field_opened');

  /// A code was checked. [source]: `typed`, `link`, `install_referrer`.
  static void referralChecked({required bool valid, required String source}) =>
      Analytics.log(valid ? 'referral_code_valid' : 'referral_code_invalid', {
        'source': source,
      });

  // ── Signed in ──────────────────────────────────────────────────────────

  /// RN `logAuthSuccess`: `auth_success`, then `sign_up` for a brand new
  /// account (once per user per install; Meta CompletedRegistration) or
  /// `login` (once per user + method per app session). Returns which one.
  ///
  /// [userKey]: documentId, else numeric id (same key as the analytics
  /// user id). [source]: `referral` when a referrer code was used, else
  /// `app`.
  static String authSuccess({
    required String? userKey,
    required String method,
    required bool isNewUser,
    required String source,
    bool otpBypass = false,
    bool phoneVerified = false,
  }) {
    final params = <String, Object?>{
      'method': method,
      'source': source,
      if (otpBypass) 'otp_bypass': true,
      if (phoneVerified) 'phone_verified': true,
    };
    Analytics.log('auth_success', {...params, 'is_new_user': isNewUser});
    final signUpKey = 'sign_up_${userKey ?? 'unknown'}';
    if (isNewUser && userKey != null && !Analytics.wasLoggedOnce(signUpKey)) {
      Analytics.logOncePersisted(signUpKey, 'sign_up', params);
      Analytics.meta('fb_mobile_complete_registration', {
        'fb_registration_method': method,
        'source': source,
      });
      return 'sign_up';
    }
    Analytics.logOnce('login_${userKey ?? 'unknown'}_$method', 'login', params);
    return 'login';
  }

  /// A sign-in that got tokens could not finish (profile read, storage).
  static void loginFailed({
    required String method,
    required String error,
    bool otpBypass = false,
  }) => Analytics.log('login_failed', {
    'method': method,
    'error': error,
    if (otpBypass) 'otp_bypass': true,
  });

  // ── Onboarding (18+ gate, languages) ───────────────────────────────────

  /// The date wheel was opened ([confirmed]: a date was picked).
  static void ageDatePicked({required bool confirmed}) =>
      Analytics.log('age_gate_date_picker', {'confirmed': confirmed});

  /// The date of birth was sent. [result]: `allowed`, `blocked`,
  /// `needs_date`, `invalid` (refused locally) or `error`.
  static void ageGateSubmitted({required String result, String? error}) =>
      Analytics.log('age_gate_submitted', {'result': result, 'error': error});

  /// The blocked (under 18) screen was shown.
  static void ageGateBlockedShown() => Analytics.log('age_gate_blocked_shown');

  /// The expert-language step saved its picks. [languages]: language
  /// documentIds, comma-joined.
  static void languageSelected({
    required String languages,
    required int count,
    String source = 'onboarding',
  }) => Analytics.log('language_selected', {
    'language': languages,
    'count': count,
    'source': source,
  });

  /// A language chip toggled on the onboarding step.
  static void languageToggled({required bool selected, required int count}) =>
      Analytics.log('onboarding_language_toggled', {
        'selected': selected,
        'count': count,
      });

  /// "Skip for now" / "Continue to the app" on the language step.
  /// [reason]: `skip` (optional question), `load_error`, `not_asked`.
  static void languageSkipped({required String reason}) =>
      Analytics.log('onboarding_language_skipped', {'reason': reason});

  static void languageSaveFailed({required String error}) =>
      Analytics.log('onboarding_language_failed', {'error': error});

  /// The post-login steps are done: the user reached Home (once per user
  /// per install). [steps]: which steps were shown on the way.
  static void onboardingCompleted({required String? userKey, String? steps}) =>
      Analytics.logOncePersisted(
        'onboarding_completed_${userKey ?? 'unknown'}',
        'onboarding_completed',
        {'steps': steps},
      );

  /// "Not you? Sign out" on an onboarding step. [screen]: `age_gate`,
  /// `language`.
  static void onboardingSignOut({required String screen}) =>
      Analytics.log('onboarding_sign_out', {'screen': screen});

  // ── Intro slides (before sign-in) ──────────────────────────────────────

  /// First slide shown (Firebase `tutorial_begin`).
  static void introStarted() {
    Analytics.log('intro_started');
    Analytics.firebase('tutorial_begin', const {});
  }

  static void introSlideViewed({required int index, required String slide}) =>
      Analytics.log('intro_slide_viewed', {'index': index, 'slide': slide});

  /// "Skip" (straight to login, or to the last slide while loading).
  static void introSkipped({required int index, required String slide}) =>
      Analytics.log('intro_skipped', {'index': index, 'slide': slide});

  /// "Get started" on the last slide (Firebase `tutorial_complete`, Meta
  /// TutorialCompletion).
  static void introCompleted({required int slides}) {
    Analytics.log('intro_completed', {'slides': slides});
    Analytics.firebase('tutorial_complete', const {});
    Analytics.meta('fb_mobile_tutorial_completion', {
      'fb_content_id': 'intro',
      'fb_success': '1',
    });
  }
}
