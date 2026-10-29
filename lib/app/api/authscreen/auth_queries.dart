import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/analytics/analytics_identity.dart';
import '../../../core/network/device_info.dart';
import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import '../../../core/storage/token_storage.dart';
import '../../../core/utils/log.dart';
import '../banner/banner_queries.dart';
import '../client/client_queries.dart';
import '../splashscreen/startup_queries.dart';
import 'auth_api.dart';
import 'auth_errors.dart';
import 'auth_keys.dart';
import 'auth_models.dart';
import 'push_api.dart';
import 'referrer_api.dart';

/// Reads the full profile right after login. Pass the client feature's
/// "user with expert" fetch; without one only `GET /public-users/:id` runs
/// and the session starts without the expert profile.
typedef SignInProfileLoader =
    Future<({JsonMap? user, JsonMap? expert})> Function(String userDocumentId);

// ── Login ────────────────────────────────────────────────────────────────

MutationResult<JsonMap, ApiException, OtpRequestInput> useRequestOtpMutation({
  void Function(JsonMap response)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<JsonMap, OtpRequestInput>(
  AuthApi.requestOtp,
  onSuccess: (response, _) => onSuccess?.call(response),
  onError: (e, _) => onError?.call(e),
);

/// Verifies the code and signs in: on success the session is set.
MutationResult<LoginResult, ApiException, OtpVerifyInput> useVerifyOtpMutation({
  SignInProfileLoader? loadProfile,
  void Function(LoginResult result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<LoginResult, OtpVerifyInput>(
  (input) => signInWithOtp(input, loadProfile: loadProfile),
  invalidates: const [AuthKeys.all],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);

/// Exchanges a provider ID token and signs in. Check
/// [LoginResult.requiresPhoneVerification] afterwards.
MutationResult<LoginResult, ApiException, SocialLoginInput>
useSocialLoginMutation({
  SignInProfileLoader? loadProfile,
  void Function(LoginResult result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<LoginResult, SocialLoginInput>(
  (input) => signInWithSocial(input, loadProfile: loadProfile),
  invalidates: const [AuthKeys.all],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);

Future<LoginResult> signInWithOtp(
  OtpVerifyInput input, {
  SignInProfileLoader? loadProfile,
}) async => _completeSignIn(
  await AuthApi.verifyOtp(input),
  loadProfile: loadProfile,
  failureKey: AuthErrorKeys.signInFailed,
);

Future<LoginResult> signInWithSocial(
  SocialLoginInput input, {
  SignInProfileLoader? loadProfile,
}) async => _completeSignIn(
  await AuthApi.socialLogin(input),
  loadProfile: loadProfile,
  failureKey: AuthErrorKeys.socialLoginFailed,
);

/// Whitelisted numbers: `/otp/request` already returned the session
/// ([LoginResult.fromBypass]); finish it like a verified code.
Future<LoginResult> signInWithBypass(
  LoginResult result, {
  SignInProfileLoader? loadProfile,
}) => _completeSignIn(
  result,
  loadProfile: loadProfile,
  failureKey: AuthErrorKeys.signInFailed,
);

/// Default profile read after login: client's "my profile" (user + expert),
/// which also fills that cache for the profile tab.
Future<({JsonMap? user, JsonMap? expert})> _loadMyProfile(String id) async {
  final p = await ensureMyProfile(id, staleDuration: StaleTime.none);
  return (user: p.user, expert: p.expert);
}

/// RN `primeCache`: warm what the first screens show ([prefetchStartup],
/// in parallel). Failures are ignored; those screens fetch on their own.
void _primeAfterSignIn(String userDocumentId) {
  prefetchStartup();
  unawaited(
    ensureUnviewedMilestones(
      userDocumentId,
    ).then((_) {}, onError: (Object _) {}),
  );
}

/// RN `setAuth` path of the login screen: tokens, profile, then the session.
Future<LoginResult> _completeSignIn(
  LoginResult result, {
  required String failureKey,
  SignInProfileLoader? loadProfile,
}) async {
  final tokens = TokenStorage.instance;
  // Tokens go first so the profile reads below carry the new user token.
  // Cleared before, so a stale refresh token cannot outlive this login.
  await tokens.clear();
  await tokens.saveTokens(
    accessToken: result.accessToken,
    refreshToken: result.refreshToken,
  );
  try {
    // Some answers carry only tokens: ask the server who they belong to.
    var user = result.user ?? await AuthApi.verifySession();
    JsonMap? expert;
    final documentId = J.str(user['documentId']);
    if (documentId != null) {
      try {
        final profile = await (loadProfile ?? _loadMyProfile)(documentId);
        // The login payload is fresher than the profile read: it wins.
        final profileUser = profile.user;
        if (profileUser != null) user = {...profileUser, ...user};
        expert = profile.expert;
      } catch (e) {
        // Non-fatal, like RN: the profile fills in on the next screen.
        Log.w('Auth', 'profile read after login failed: $e');
      }
    }
    user = AuthUser.normalize(user);
    await SessionStore.instance.signIn(
      user: user,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expert: expert,
    );
    if (documentId != null) _primeAfterSignIn(documentId);
    return result.copyWith(user: user, expert: expert);
  } catch (e, st) {
    // A half-stored session must not be restored on the next launch.
    await tokens.clear();
    throw AuthErrors.login(
      ApiException.from(e, st),
      rejectedKey: failureKey,
      fallbackKey: failureKey,
    );
  }
}

// ── Logout ───────────────────────────────────────────────────────────────

MutationResult<void, ApiException, LogoutInput> useLogoutMutation({
  void Function()? onSuccess,
}) => useApiMutation<void, LogoutInput>(
  logout,
  onSuccess: (_, _) => onSuccess?.call(),
);

/// Server cleanup gets this long before the local sign-out happens anyway.
const _logoutCleanupLimit = Duration(seconds: 8);

/// Signs out on the server and on the device (RN `clearAuth`). Never throws:
/// the local sign-out always happens.
///
/// The server cleanup runs first: it needs the user's token, and
/// `SessionStore.signOut` wipes it and blocks every non-auth request.
Future<void> logout([LogoutInput input = const LogoutInput()]) async {
  AnalyticsIdentity.markSignOut('user');
  try {
    await _serverLogout(
      input,
      SessionStore.instance.value,
    ).timeout(_logoutCleanupLimit);
  } catch (e) {
    Log.w('Auth', 'server logout incomplete: $e');
  } finally {
    await SessionStore.instance.signOut();
  }
}

Future<void> _serverLogout(LogoutInput input, SessionState session) async {
  final accessToken = await TokenStorage.instance.readAccessToken();
  final refreshToken = await TokenStorage.instance.readRefreshToken();
  // This install's stored tokens when the caller passed none (push layer).
  final fcmToken = J.str(input.fcmToken) ?? PushTokens.fcm;
  final voipToken = J.str(input.voipToken) ?? PushTokens.voip;
  final userId = session.userKey;
  final deviceId = (await DeviceInfo.get())['deviceId']?.toString();

  // Both need the user's token, so they run before the session is revoked.
  await Future.wait([
    if (fcmToken != null && J.str(accessToken) != null)
      runBestEffort(
        'device unregister',
        () => PushApi.unregisterDevice(
          fcmToken: fcmToken,
          voipToken: voipToken,
          accessToken: accessToken,
        ),
      ),
    if (userId != null)
      runBestEffort(
        'push token clear',
        () => PushApi.clearPushTokens(userId, deviceId: deviceId),
      ),
  ]);
  await runBestEffort(
    'session revoke',
    () => AuthApi.logout(refreshToken: refreshToken),
  );
}

// ── Signed-in user ───────────────────────────────────────────────────────

/// The user behind the current token (`/auth/verify-token`).
QueryResult<JsonMap, ApiException> useVerifiedUser(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<JsonMap>(
  AuthKeys.sessionUser,
  AuthApi.verifySession,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.short,
);

Future<JsonMap> ensureVerifiedUser() =>
    queryCache.fetchQuery<JsonMap>(AuthKeys.sessionUser, AuthApi.verifySession);

/// Public-user with profile picture; defaults to the signed-in user.
QueryResult<JsonMap, ApiException> useUserByDocumentId(
  BuildContext context, {
  String? documentId,
}) {
  final id = documentId ?? SessionStore.instance.value.userDocumentId;
  return useApiQuery<JsonMap>(
    AuthKeys.user(id ?? ''),
    () => AuthApi.fetchUser(id!),
    context: context,
    enabled: id != null,
    staleDuration: StaleTime.short,
  );
}

Future<JsonMap> ensureUserByDocumentId(String documentId) =>
    queryCache.fetchQuery<JsonMap>(
      AuthKeys.user(documentId),
      () => AuthApi.fetchUser(documentId),
    );

/// Re-reads the signed-in user and merges it into the session (RN
/// `updateUser`). Returns the fresh user.
Future<JsonMap> refreshSessionUser() async {
  final store = SessionStore.instance;
  final documentId = store.value.userDocumentId;
  if (documentId == null) {
    throw const ApiException(ApiErrorType.unauthorized);
  }
  final fresh = await queryCache.fetchQuery<JsonMap>(
    AuthKeys.user(documentId),
    () => AuthApi.fetchUser(documentId),
    staleDuration: StaleTime.none,
  );
  // Ignore a late answer for an account that has since signed out or switched.
  if (store.value.userDocumentId == documentId) {
    await store.updateUser(AuthUser.normalize(fresh));
  }
  return fresh;
}

// ── Referrals ────────────────────────────────────────────────────────────

/// "Invited by …" check for a typed or captured code. Debounce in the UI.
QueryResult<ReferralCheck, ApiException> useReferralCheck(
  BuildContext context,
  String code,
) {
  final normalized = ReferrerApi.normalizeCode(code);
  return useApiQuery<ReferralCheck>(
    AuthKeys.referral(normalized),
    () => ReferrerApi.validateCode(normalized),
    context: context,
    enabled: normalized.isNotEmpty,
    staleDuration: StaleTime.medium,
  );
}

/// Host to open after login for an install-referrer code. Null when the code
/// is unknown or the lookup fails: a referral must never block sign-in
/// (RN degraded the same way).
Future<ReferrerTarget?> resolveReferrerTarget(String handler) async {
  try {
    return await ReferrerApi.resolveTarget(handler);
  } on ApiException catch (e) {
    Log.w('Auth', 'referrer lookup failed: $e');
    return null;
  }
}
