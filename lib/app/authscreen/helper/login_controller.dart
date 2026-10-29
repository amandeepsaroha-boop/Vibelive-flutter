import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/analytics_identity.dart';
import '../../../core/analytics/events/auth_events.dart';
import '../../../core/analytics/screen_tracker.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../../api/authscreen/auth_api.dart';
import '../../api/authscreen/auth_errors.dart';
import '../../api/authscreen/auth_models.dart';
import '../../api/authscreen/auth_queries.dart';
import '../../component/c_input.dart';
import 'auth_navigation.dart';
import 'deep_links.dart';
import 'link_parser.dart';
import 'login_format.dart';
import 'login_referral.dart';
import 'sms_otp_autofill.dart';
import 'social_sign_in.dart';
import 'terms_consent.dart';

export 'login_referral.dart' show ReferralStatus;

/// Text for the UI: an i18n key, or a server message shown as-is.
@immutable
class UiText {
  const UiText(this.value, {this.raw = false});

  factory UiText.of(ApiException e) =>
      e.serverMessage != null && e.type != ApiErrorType.server
      ? UiText(e.serverMessage!, raw: true)
      : UiText(e.i18nKey);

  final String value;
  final bool raw;
}

/// Everything the sign-in screen does (RN `LoginScreen.jsx` logic): the
/// options page (Google / Apple, then mobile or email), the email / mobile
/// sheet with its code step, OTP auto-fill, referral, first-time terms
/// consent, and the hand-off to age gate / language / Home.
///
/// State is split into small notifiers so each part of the screen rebuilds
/// only for its own change (the resend countdown ticks one label, OTP digits
/// repaint four boxes, …).
class LoginController {
  LoginController({
    required this.navigate,
    required this.askConsent,
    Map<String, String> routeParams = const {},
  }) : referral = LoginReferral(routeParams) {
    SocialSignIn.appleAvailable().then((v) => _set(appleAvailable, v));
    if (kDebugMode) {
      // The hash the backend must append for Android auto-fill.
      SmsOtpAutofill.instance.appHashes().then((h) {
        if (h.isNotEmpty) Log.d('SmsOtp', 'app hash (autofillCode): $h');
      });
    }
  }

  /// Replaces the stack with [route] (nothing to go back to).
  final void Function(String route) navigate;

  /// Shows the consent page; true when accepted.
  final Future<bool> Function(String provider) askConsent;

  final LoginReferral referral;
  final email = TextEditingController();
  final phone = TextEditingController();
  final otp = TextEditingController();
  final otpFocus = FocusNode();

  /// null: the sign-in options; otherwise the sheet for that method.
  final method = ValueNotifier<OtpChannel?>(null);

  /// The backend wants a phone number from a social user: the sheet is the
  /// only way forward (no close, no switching to email).
  final phoneRequired = ValueNotifier(false);
  final otpSent = ValueNotifier(false);
  final termsAccepted = ValueNotifier(false);

  /// SEND OTP tapped with the box unticked: the checkbox turns red.
  final termsNudge = ValueNotifier(false);
  final busy = ValueNotifier(false);
  final socialBusy = ValueNotifier<SocialProvider?>(null);
  final error = ValueNotifier<UiText?>(null);
  final resendIn = ValueNotifier(0);
  final resending = ValueNotifier(false);

  /// Brief highlight after the code arrives from SMS / the keyboard.
  final otpAutoFilled = ValueNotifier(false);
  final appleAvailable = ValueNotifier(false);

  bool _submitting = false; // sync guard: no double submit before a rebuild
  bool _disposed = false;
  bool _phoneHintAsked = false;
  int _otpLength = 0;

  /// The number the last code went to: a 429 for it means that code stands.
  String _lastSent = '';
  VoidCallback? _stopSms;
  Timer? _resendTimer, _autoFilledTimer;

  bool get _isEmail => method.value == OtpChannel.email;
  OtpChannel get _channel => method.value ?? OtpChannel.sms;

  /// Analytics `method` of the open sheet: `email` or `phone`.
  String get _method => _isEmail ? 'email' : 'phone';

  /// The social provider whose user must verify a mobile: the OTP that
  /// follows completes THAT sign-in (analytics method = the provider).
  SocialProvider? _socialPending;

  /// The sheet's current step as an analytics screen name: `login`,
  /// `login_mobile`, `login_email`, `login_otp_mobile`, `login_otp_email`,
  /// `login_phone_required`.
  String get screenName {
    final m = method.value;
    if (m == null) return 'login';
    final channel = m == OtpChannel.email ? 'email' : 'mobile';
    if (otpSent.value) return 'login_otp_$channel';
    return phoneRequired.value ? 'login_phone_required' : 'login_$channel';
  }

  void _viewStep() => ScreenTracker.view(screenName);

  String get _identifier => _isEmail
      ? email.text.trim().toLowerCase()
      : IndianMobileFormatter.normalize(phone.text);

  /// `ab***@mail.com` / `+91 98765 43210`, for "Sent to …".
  String get sentTo => _isEmail
      ? LoginFormat.maskEmail(email.text)
      : '+91 ${LoginFormat.formatMobile(_identifier)}';

  void clearError() {
    if (error.value != null) error.value = null;
  }

  void toggleTerms() {
    termsAccepted.value = !termsAccepted.value;
    termsNudge.value = false;
    AuthEvents.termsToggled(accepted: termsAccepted.value);
  }

  // ── Options ⇄ sheet ────────────────────────────────────────────────────

  /// Typed values are kept, so closing and reopening (or switching) is free.
  /// [source]: analytics, `options` or `switch` (the link in the sheet).
  void openMethod(OtpChannel channel, {String source = 'options'}) {
    method.value = channel;
    clearError();
    termsNudge.value = false;
    AuthEvents.methodSelected(
      channel == OtpChannel.email ? 'email' : 'phone',
      source: source,
    );
    _viewStep();
  }

  /// Closes the sheet. A pending code is dropped; asking again for the same
  /// number inside the cooldown lands straight back on it (see [sendOtp]).
  void closeSheet() {
    if (method.value != null) {
      AuthEvents.sheetClosed(method: _method, otpSent: otpSent.value);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _stopSmsAutofill();
    otpSent.value = false;
    otp.clear();
    method.value = null;
    clearError();
    termsNudge.value = false;
    _viewStep();
  }

  /// Android back: code step → form → closed; the options page itself is
  /// not handled here (a second press exits).
  bool handleBack() {
    if (method.value == null) return false;
    if (otpSent.value) {
      editIdentifier();
    } else if (!phoneRequired.value) {
      closeSheet();
    }
    return true;
  }

  /// "Change" / Back on the code step: back to the email / mobile form.
  void editIdentifier() {
    AuthEvents.otpChangeIdentifier(method: _method);
    _stopSmsAutofill();
    otpSent.value = false;
    otp.clear();
    clearError();
    _viewStep();
  }

  // ── OTP ────────────────────────────────────────────────────────────────

  Future<void> sendOtp() async {
    if (_submitting || busy.value) return;
    final identifier = _identifier;
    final valid = _isEmail
        ? LoginFormat.isValidEmail(identifier)
        : LoginFormat.isValidIndianMobile(identifier);
    if (!valid) {
      AuthEvents.inputInvalid(
        method: _method,
        field: _isEmail ? 'email' : 'phone',
      );
      return _set(
        error,
        UiText(
          _isEmail
              ? 'auth:login.errors.invalid_email'
              : 'auth:login.errors.invalid_phone',
        ),
      );
    }
    if (!termsAccepted.value) {
      AuthEvents.termsRequired(method: _method);
      return _set(termsNudge, true);
    }

    _lock();
    FocusManager.instance.primaryFocus?.unfocus();
    // Armed BEFORE the request: the retriever only sees later messages.
    if (!_isEmail) _startSmsAutofill();
    var handedOff = false;
    try {
      final response = await AuthApi.requestOtp(
        OtpRequestInput(identifier: identifier, channel: _channel),
      );
      final bypass = LoginResult.fromBypass(response);
      if (bypass != null) {
        _stopSmsAutofill();
        handedOff = true;
        await _completeSignIn(() => signInWithBypass(bypass), bypass: true);
        return;
      }
      _lastSent = identifier;
      AuthEvents.otpRequested(method: _method);
      _showCodeStep(LoginFormat.resendSeconds);
    } on ApiException catch (e) {
      final retryAfter = AuthErrors.retryAfterSeconds(e);
      // Still in the cooldown for the number that already got a code (e.g.
      // "Change" and straight back): that code is still valid, go to it.
      if (retryAfter > 0 && identifier == _lastSent) {
        AuthEvents.otpRequested(method: _method, cooldownResume: true);
        return _showCodeStep(retryAfter);
      }
      AuthEvents.otpRequestFailed(
        method: _method,
        error: Analytics.errorCode(e),
      );
      _stopSmsAutofill();
      _set(error, UiText.of(e));
    } finally {
      if (!handedOff) _unlock(const Duration(milliseconds: 100));
    }
  }

  void _showCodeStep(int resendSeconds) {
    otp.clear();
    _otpLength = 0;
    _set(otpSent, true);
    _startResendTimer(resendSeconds);
    if (!_disposed) _viewStep();
  }

  /// Every change of the hidden code field. All four digits at once (the
  /// keyboard suggestion or a paste) count as auto-filled; four digits
  /// verify straight away (RN).
  void onOtpChanged(String value) {
    final code = value.replaceAll(RegExp(r'\D'), '');
    if (code.length == otpLength && _otpLength == 0) {
      AuthEvents.otpAutofilled(method: _method, source: 'keyboard');
      _flashAutoFilled();
    }
    _otpLength = code.length;
    clearError();
    if (code.length == otpLength) verifyOtp();
  }

  Future<void> verifyOtp() async {
    if (_submitting || busy.value) return;
    final digits = otp.text.replaceAll(RegExp(r'\D'), '');
    final code = digits.length > otpLength
        ? digits.substring(0, otpLength)
        : digits;
    if (code.length < otpLength) {
      AuthEvents.inputInvalid(method: _method, field: 'code');
      return _set(error, const UiText('auth:login.errors.enter_code'));
    }
    final signedIn = await _completeSignIn(
      () => signInWithOtp(
        OtpVerifyInput(
          identifier: _identifier,
          code: code,
          channel: _channel,
          referrerCode: referral.backendCode(),
        ),
      ),
    );
    // Wrong / expired code: clear the boxes for the next attempt.
    if (!signedIn && !_disposed) {
      otp.clear();
      _otpLength = 0;
      Timer(const Duration(milliseconds: 250), () {
        if (!_disposed) otpFocus.requestFocus();
      });
    }
  }

  Future<void> resend() async {
    if (resendIn.value > 0 || resending.value || busy.value) return;
    _set(resending, true);
    clearError();
    // Re-armed so the new message is caught too (one message per start).
    if (!_isEmail) _startSmsAutofill();
    try {
      await AuthApi.requestOtp(
        OtpRequestInput(identifier: _identifier, channel: _channel),
      );
      otp.clear();
      _otpLength = 0;
      _startResendTimer(LoginFormat.resendSeconds);
      AuthEvents.otpResent(method: _method);
      if (!_disposed) otpFocus.requestFocus();
    } on ApiException catch (e) {
      AuthEvents.otpResendFailed(
        method: _method,
        error: Analytics.errorCode(e),
      );
      final retryAfter = AuthErrors.retryAfterSeconds(e);
      if (retryAfter > 0) _startResendTimer(retryAfter);
      _set(
        error,
        e.messageKey == AuthErrorKeys.otpSendFailed
            ? const UiText('auth:login.errors.resend_failed')
            : UiText.of(e),
      );
    } finally {
      _set(resending, false);
    }
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    _set(resendIn, seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed || resendIn.value <= 1) t.cancel();
      _set(resendIn, resendIn.value - 1);
    });
  }

  /// Session from [run], then on to the next route. Owns the submit lock;
  /// stays busy on success while the screen navigates away. [bypass]: a
  /// whitelisted number signed in by `/otp/request` itself (analytics).
  Future<bool> _completeSignIn(
    Future<LoginResult> Function() run, {
    bool bypass = false,
  }) async {
    _lock();
    final social = _socialPending;
    final method = social?.name ?? _method;
    try {
      final result = await run();
      _socialPending = null;
      _logSignedIn(
        result,
        method: method,
        otpBypass: bypass,
        phoneVerified: social != null,
      );
      _stopSmsAutofill();
      await _leave();
      return true;
    } on ApiException catch (e) {
      final code = Analytics.errorCode(e);
      if (bypass) {
        AuthEvents.loginFailed(method: method, error: code, otpBypass: true);
      } else {
        AuthEvents.otpVerifyFailed(method: _method, error: code);
      }
      _set(error, UiText.of(e));
      _unlock(const Duration(milliseconds: 200));
      return false;
    }
  }

  /// `auth_success` + `sign_up` (new account) or `login` (RN
  /// `logAuthSuccess`), with how the user signed in.
  void _logSignedIn(
    LoginResult result, {
    required String method,
    bool otpBypass = false,
    bool phoneVerified = false,
  }) {
    final session = SessionStore.instance.value;
    final user = result.user;
    AuthEvents.authSuccess(
      userKey:
          session.userDocumentId ??
          session.userId?.toString() ??
          J.str(user?['documentId']) ??
          J.str(user?['id']),
      method: method,
      isNewUser: result.isNewUser,
      source: referral.backendCode() != null ? 'referral' : 'app',
      otpBypass: otpBypass,
      phoneVerified: phoneVerified,
    );
  }

  // ── Auto-fill (Android SMS Retriever; iOS uses the keyboard) ───────────

  void _startSmsAutofill() {
    _stopSmsAutofill();
    _stopSms = SmsOtpAutofill.instance.listen((code) {
      _stopSms = null;
      if (_disposed) return;
      AuthEvents.otpAutofilled(method: _method, source: 'sms_retriever');
      otp.text = code;
      _otpLength = code.length;
      _flashAutoFilled();
      clearError();
      verifyOtp();
    });
  }

  void _stopSmsAutofill() {
    _stopSms?.call();
    _stopSms = null;
  }

  void _flashAutoFilled() {
    _set(otpAutoFilled, true);
    _autoFilledTimer?.cancel();
    _autoFilledTimer = Timer(
      const Duration(milliseconds: 1600),
      () => _set(otpAutoFilled, false),
    );
  }

  /// Android: the SIM-number picker, offered once, when the empty mobile
  /// field first gets focus. iOS suggests the number on the keyboard.
  Future<void> offerPhoneHint() async {
    final autofill = SmsOtpAutofill.instance;
    if (!autofill.isSupported || _phoneHintAsked || phone.text.isNotEmpty) {
      return;
    }
    _phoneHintAsked = true;
    final picked = await autofill.requestPhoneHint();
    AuthEvents.phoneHint(picked: picked != null);
    if (picked == null || _disposed) return;
    final number = IndianMobileFormatter.normalize(picked);
    phone.value = TextEditingValue(
      text: number,
      selection: TextSelection.collapsed(offset: number.length),
    );
    clearError();
  }

  // ── Google / Apple ─────────────────────────────────────────────────────

  Future<void> social(SocialProvider provider) async {
    if (_submitting || busy.value || socialBusy.value != null) return;
    _set(socialBusy, provider);
    clearError();
    final name = provider.name;
    AuthEvents.methodSelected(name);
    AuthEvents.socialStarted(name);

    final String? idToken;
    try {
      idToken = provider == SocialProvider.apple
          ? await SocialSignIn.apple()
          : await SocialSignIn.google();
    } catch (e, st) {
      Log.e('Login', e, st);
      AuthEvents.socialFailed(
        name,
        error: Analytics.errorCode(e),
        stage: 'provider',
      );
      _set(socialBusy, null);
      return _set(error, const UiText(AuthErrorKeys.socialLoginFailed));
    }
    if (idToken == null) {
      AuthEvents.socialCancelled(name);
      return _set(socialBusy, null); // closed the sheet
    }

    _lock();
    try {
      final result = await signInWithSocial(
        SocialLoginInput(
          provider: provider,
          idToken: idToken,
          referrerCode: referral.backendCode(),
        ),
      );
      unawaited(SocialSignIn.signOut());

      if (result.requiresPhoneVerification) {
        _socialPending = provider;
        AuthEvents.socialPhoneRequired(name);
        AuthEvents.methodSelected('phone', source: 'phone_required');
        _set(phoneRequired, true);
        _set(method, OtpChannel.sms);
        _set(otpSent, false);
        _set(error, const UiText('auth:login.errors.phone_required'));
        if (!_disposed) _viewStep();
        return _unlock(Duration.zero);
      }

      // Social sign-in skips the checkbox: ask once per user + terms version.
      final user = result.user;
      final userId = J.str(user?['documentId']) ?? J.str(user?['id']);
      if (TermsConsent.needed(userId, provider.name)) {
        _set(busy, false); // the page must be usable
        _set(socialBusy, null);
        AuthEvents.termsConsentShown(name);
        if (!await askConsent(provider.name)) {
          AuthEvents.termsConsentDeclined(name);
          // Declined: the stored session must not survive to the next launch.
          AnalyticsIdentity.markSignOut('terms_declined');
          await SessionStore.instance.signOut();
          _set(error, const UiText('auth:login.errors.terms_required'));
          return _unlock(Duration.zero);
        }
        AuthEvents.termsConsentAccepted(name);
        await TermsConsent.accept(userId, provider.name);
        _set(busy, true);
      }
      _logSignedIn(result, method: name);
      return _leave();
    } on ApiException catch (e) {
      AuthEvents.socialFailed(
        name,
        error: Analytics.errorCode(e),
        stage: 'server',
      );
      _set(error, UiText.of(e));
    }
    _unlock(const Duration(milliseconds: 200));
  }

  // ── After sign-in ──────────────────────────────────────────────────────

  /// Host to open from a pending share link or the referrer, then age gate
  /// → language → Home (RN `executePostLoginRouting`).
  Future<void> _leave() async {
    final pending = DeepLinks.instance.takeLink();
    final openUser =
        (pending == null ? null : LinkParser.parse(pending)?.openUserId) ??
        await referral.hostToOpen();
    if (openUser != null) DeepLinks.instance.setOpenUser(openUser);
    final route = await nextAuthRoute();
    if (!_disposed) navigate(route);
  }

  // ── Plumbing ───────────────────────────────────────────────────────────

  void _lock() {
    _submitting = true;
    _set(busy, true);
    clearError();
  }

  void _unlock(Duration delay) {
    _set(busy, false);
    _set(socialBusy, null);
    Future<void>.delayed(delay, () => _submitting = false);
  }

  void _set<T>(ValueNotifier<T> notifier, T value) {
    if (!_disposed) notifier.value = value;
  }

  void dispose() {
    _disposed = true;
    _stopSmsAutofill();
    _resendTimer?.cancel();
    _autoFilledTimer?.cancel();
    referral.dispose();
    otpFocus.dispose();
    for (final c in [email, phone, otp]) {
      c.dispose();
    }
    for (final n in <ChangeNotifier>[
      method, phoneRequired, otpSent, termsAccepted, termsNudge, busy, //
      socialBusy, error, resendIn, resending, otpAutoFilled, appleAvailable,
    ]) {
      n.dispose();
    }
  }
}
