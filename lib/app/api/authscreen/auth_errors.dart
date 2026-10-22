import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/log.dart';

/// i18n keys (namespace `auth`) used by the auth API layer.
abstract final class AuthErrorKeys {
  static const otpSendFailed = 'auth:errors.otp_send_failed';
  static const invalidOtp = 'auth:errors.invalid_otp';
  static const signInFailed = 'auth:errors.sign_in_failed';
  static const socialLoginFailed = 'auth:errors.social_login_failed';
  static const dobIncomplete = 'auth:errors.dob_incomplete';
  static const dobInvalid = 'auth:errors.dob_invalid';
  static const dobFuture = 'auth:errors.dob_future';
  static const dobSaveFailed = 'auth:errors.dob_save_failed';
  static const interestsSyncFailed = 'auth:errors.interests_sync_failed';
}

/// Error copy for the auth flows, as the RN app chose it (`authErrors.js`,
/// `describeAgeGateError`, the language step's `describeSaveError`). Each
/// takes the caught exception and returns the one to throw.
abstract final class AuthErrors {
  /// OTP and social login (RN `describeAuthError`). A readable server message
  /// still wins ("OTP expired"); without one, a refused request (400/401/422)
  /// shows [rejectedKey] and any other non-transport failure [fallbackKey].
  static ApiException login(
    ApiException e, {
    required String rejectedKey,
    required String fallbackKey,
  }) {
    if (_isTransport(e.type)) return e;
    if (e.type == ApiErrorType.rejected ||
        e.type == ApiErrorType.unauthorized) {
      // A 401 here refuses the code or token; it is not an expired session.
      return e.copyWith(type: ApiErrorType.rejected, messageKey: rejectedKey);
    }
    return e.copyWith(messageKey: fallbackKey);
  }

  /// PUT /me/date-of-birth (RN `describeAgeGateError`). Known server codes
  /// get their own copy; the server's own text is never shown.
  static ApiException dateOfBirth(ApiException e) {
    final known = switch (serverCode(e)) {
      'DATE_OF_BIRTH_INVALID' => AuthErrorKeys.dobInvalid,
      'DATE_OF_BIRTH_IN_FUTURE' => AuthErrorKeys.dobFuture,
      _ => null,
    };
    if (known != null) {
      return _ownCopy(e, known, type: ApiErrorType.rejected);
    }
    if (_isTransport(e.type)) return _ownCopy(e, null);
    if (e.type == ApiErrorType.unauthorized) return _ownCopy(e, _expired);
    return _ownCopy(e, AuthErrorKeys.dobSaveFailed);
  }

  /// Saving the onboarding language answer (RN `describeSaveError`):
  /// transport failures keep their copy, anything else is "on our side".
  static ApiException languageSave(ApiException e) {
    if (_isTransport(e.type)) return _ownCopy(e, null);
    if (e.type == ApiErrorType.unauthorized) return _ownCopy(e, _expired);
    return _ownCopy(e, ApiException.defaultKeyFor(ApiErrorType.server));
  }

  /// Interests form and answers (RN `parseInterestError` fallback copy).
  static ApiException interests(ApiException e) =>
      _isTransport(e.type) || e.type == ApiErrorType.unauthorized
      ? e
      : e.copyWith(messageKey: AuthErrorKeys.interestsSyncFailed);

  /// Seconds a refused OTP request asks to wait: `error.details.retryAfter`,
  /// else the `Retry-After` header (RN `getRetryAfterSeconds`). 0 = none.
  static int retryAfterSeconds(ApiException e) {
    final data = e.data;
    final error = data is Map ? data['error'] : null;
    final details = error is Map ? error['details'] : null;
    Object? raw = details is Map ? details['retryAfter'] : null;
    final cause = e.cause;
    if (raw == null && cause is DioException) {
      raw = cause.response?.headers.value('retry-after');
    }
    final seconds = num.tryParse('${raw ?? ''}');
    return seconds == null || !seconds.isFinite || seconds <= 0
        ? 0
        : seconds.ceil();
  }

  /// Error code the backend puts in `error.message` or `message`
  /// (`AGE_BLOCKED`, `DATE_OF_BIRTH_INVALID`…).
  static String? serverCode(ApiException e) {
    final data = e.data;
    if (data is! Map) return null;
    final error = data['error'];
    return _text(error is Map ? error['message'] : null) ??
        _text(data['message']);
  }

  static final _expired = ApiException.defaultKeyFor(
    ApiErrorType.sessionExpired,
  );

  static bool _isTransport(ApiErrorType type) => switch (type) {
    ApiErrorType.network ||
    ApiErrorType.timeout ||
    ApiErrorType.cancelled ||
    ApiErrorType.rateLimited ||
    ApiErrorType.server ||
    ApiErrorType.loggingOut ||
    ApiErrorType.sessionExpired => true,
    _ => false,
  };

  /// Same failure without the server's text, so [key] (or the default copy
  /// for the type) is what the user sees.
  static ApiException _ownCopy(
    ApiException e,
    String? key, {
    ApiErrorType? type,
  }) => ApiException(
    type ?? e.type,
    statusCode: e.statusCode,
    messageKey: key,
    data: e.data,
    cause: e.cause,
    stackTrace: e.stackTrace,
  );
}

/// Details of a refused `/me/interests` call (RN `parseInterestError`), e.g.
/// `REQUIRED_QUESTION_MISSING` with per-question details.
extension InterestErrorInfo on ApiException {
  String? get interestErrorCode {
    final data = this.data;
    if (data is! Map) return null;
    final error = data['error'] is Map ? data['error'] as Map : const {};
    return _text(error['code']) ??
        _text(error['name']) ??
        _text(data['code']) ??
        _text(data['errorCode']);
  }

  Object? get interestErrorDetails {
    final data = this.data;
    if (data is! Map) return null;
    final error = data['error'];
    return (error is Map ? error['details'] : null) ?? data['details'];
  }
}

extension ApiTimeout<T> on Future<T> {
  /// Bounds a request that gates navigation (RN `withTimeout`). Only the wait
  /// ends; the request itself keeps running.
  Future<T> withApiTimeout(Duration limit) => timeout(
    limit,
    onTimeout: () => throw const ApiException(ApiErrorType.timeout),
  );
}

/// Runs a cleanup call whose failure must not stop the flow around it
/// (logout, push token sync): the failure is logged and dropped.
Future<void> runBestEffort(String what, Future<void> Function() call) async {
  try {
    await call();
  } catch (e) {
    Log.w('Auth', '$what failed: $e');
  }
}

String? _text(Object? value) {
  final s = value?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}
