import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/device_info.dart';
import '../../../core/network/strapi.dart';
import 'auth_errors.dart';
import 'auth_models.dart';
import 'push_api.dart';

/// Session auth (OTP, social, logout), the signed-in user and the age gate.
/// No caching or session state here: see `auth_queries.dart` and
/// `onboarding_queries.dart`.
///
/// Token refresh lives in `ApiClient`. OTP and social calls go without a
/// token, like RN (`_skipAuthToken`).
abstract final class AuthApi {
  /// GET /me decides where login and cold start land: bounded, no retries.
  static const meTimeout = Duration(seconds: 6);

  /// Returns the raw answer (the app only needs the call to succeed).
  static Future<JsonMap> requestOtp(OtpRequestInput input) async {
    try {
      final body = await ApiClient.post(
        '/session-auth/otp/request',
        data: {
          'identifier': input.channel.normalize(input.identifier),
          'channel': input.channel.name,
          'platform': DeviceInfo.platform,
          'userPlatform': Env.appPlatform,
          'deviceInfo': await DeviceInfo.get(),
        },
        skipAuth: true,
      );
      return body is Map
          ? Map<String, dynamic>.from(body)
          : <String, dynamic>{};
    } on ApiException catch (e) {
      throw AuthErrors.login(
        e,
        rejectedKey: AuthErrorKeys.otpSendFailed,
        fallbackKey: AuthErrorKeys.otpSendFailed,
      );
    }
  }

  static Future<LoginResult> verifyOtp(OtpVerifyInput input) async => _login(
    '/session-auth/otp/verify',
    {
      'identifier': input.channel.normalize(input.identifier),
      'channel': input.channel.name,
      'code': input.code.trim(),
      ...await _extras(input.referrerCode, input.fcmToken, input.voipToken),
    },
    rejectedKey: AuthErrorKeys.invalidOtp,
    fallbackKey: AuthErrorKeys.signInFailed,
  );

  /// [SocialLoginInput.idToken] comes from the provider SDK (out of scope
  /// here). A 401 is retried once with the app token by `ApiClient`.
  static Future<LoginResult> socialLogin(SocialLoginInput input) async =>
      _login(
        '/session-auth/social/exchange',
        {
          'provider': input.provider.name,
          'idToken': input.idToken,
          ...await _extras(input.referrerCode, input.fcmToken, input.voipToken),
        },
        rejectedKey: AuthErrorKeys.socialLoginFailed,
        fallbackKey: AuthErrorKeys.socialLoginFailed,
      );

  /// Revokes the session server-side. Sent with the user's token; being a
  /// session-auth route, a 401 never starts a refresh.
  static Future<void> logout({String? refreshToken}) async {
    await ApiClient.post(
      '/session-auth/logout',
      data: {
        'refreshToken': ?J.str(refreshToken),
        'deviceInfo': await DeviceInfo.get(),
      },
    );
  }

  /// The user behind the current token (`/auth/verify-token`).
  static Future<JsonMap> verifySession() async {
    final body = await ApiClient.get('/auth/verify-token');
    final root = body is Map ? body : const {};
    final user =
        Strapi.map(root['user']) ??
        Strapi.map(Strapi.map(root['data'])?['user']);
    if (user == null) throw ApiException(ApiErrorType.parse, data: body);
    return user;
  }

  /// Public-user by documentId with its profile picture.
  static Future<JsonMap> fetchUser(String documentId) async {
    final body = await ApiClient.get(
      '/public-users/${Uri.encodeComponent(documentId)}',
      query: {'populate[profilePic]': 'true'},
    );
    final user = Strapi.map(Strapi.body(body));
    if (user == null) throw ApiException(ApiErrorType.notFound, data: body);
    return user;
  }

  /// GET /me: the user with the server's age verdict (`ageGateStatus`).
  static Future<JsonMap?> fetchMe() async {
    final body = await ApiClient.get(
      '/me',
      retry: false,
    ).withApiTimeout(meTimeout);
    return body is Map ? Strapi.map(body['user']) : null;
  }

  /// The server decides eligibility: `ok`, or `blocked` when under 18
  /// (terminal). Anything else throws with copy ready to show.
  static Future<AgeGateStatus> submitDateOfBirth(String isoDate) async {
    try {
      await ApiClient.put('/me/date-of-birth', data: {'dateOfBirth': isoDate});
      return AgeGateStatus.ok;
    } on ApiException catch (e) {
      if (AuthErrors.serverCode(e) == 'AGE_BLOCKED') {
        return AgeGateStatus.blocked;
      }
      throw AuthErrors.dateOfBirth(e);
    }
  }

  static Future<LoginResult> _login(
    String path,
    JsonMap payload, {
    required String rejectedKey,
    required String fallbackKey,
  }) async {
    try {
      final body = await ApiClient.post(
        path,
        data: {
          ...payload,
          'platform': DeviceInfo.platform,
          'userPlatform': Env.appPlatform,
          // Session-auth binds the new session's push tokens from
          // `deviceInfo.*` (RN `deviceInfoWithTokens`): the multi-device ring
          // target. Top-level copies stay for older backends.
          'deviceInfo': {
            ...await DeviceInfo.get(),
            'fcmToken': ?J.str(payload['fcmToken']),
            'voipToken': ?J.str(payload['voipToken']),
          },
        },
        skipAuth: true,
      );
      final result = LoginResult.fromResponse(body);
      if (result == null) throw ApiException(ApiErrorType.parse, data: body);
      return result;
    } on ApiException catch (e) {
      throw AuthErrors.login(
        e,
        rejectedKey: rejectedKey,
        fallbackKey: fallbackKey,
      );
    }
  }

  /// The caller's tokens win; otherwise this install's stored ones (the
  /// VoIP token is read up to 3 × 1.5 s on iOS, RN `LoginScreen`).
  static Future<JsonMap> _extras(
    String? referrerCode,
    String? fcmToken,
    String? voipToken,
  ) async => {
    'referrerCode': ?J.str(referrerCode),
    'fcmToken': ?(J.str(fcmToken) ?? PushTokens.fcm),
    'voipToken': ?(J.str(voipToken) ?? await PushTokens.voipForLogin()),
  };
}
