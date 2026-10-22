import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../i18n/i18n.dart';

enum ApiErrorType {
  /// No connection / DNS / socket failure.
  network,
  timeout,
  cancelled,

  /// 400 / 422 (and 401 on auth endpoints): the server refused the input.
  rejected,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  rateLimited,
  server,

  /// Refresh failed: the user has to log in again.
  sessionExpired,

  /// Request dropped because logout is in progress.
  loggingOut,

  /// Response arrived but could not be parsed into the expected shape.
  parse,
  unknown,
}

/// The only error type the API layer throws. fquery casts errors to the
/// query's error type, so every query/mutation uses `ApiException`.
class ApiException implements Exception {
  const ApiException(
    this.type, {
    this.statusCode,
    this.serverMessage,
    this.messageKey,
    this.data,
    this.cause,
    this.stackTrace,
  });

  final ApiErrorType type;
  final int? statusCode;

  /// Human-readable message from the backend, when it sent one.
  final String? serverMessage;

  /// Feature-specific i18n key that overrides the default copy for [type].
  final String? messageKey;

  /// Raw response body.
  final Object? data;
  final Object? cause;
  final StackTrace? stackTrace;

  /// Worth retrying automatically (network blips, 408/429/5xx).
  bool get isTransient =>
      type == ApiErrorType.network ||
      type == ApiErrorType.timeout ||
      type == ApiErrorType.rateLimited ||
      type == ApiErrorType.server ||
      statusCode == 408;

  bool get isAuthError =>
      type == ApiErrorType.unauthorized || type == ApiErrorType.sessionExpired;

  /// i18n key (common namespace) describing this error.
  String get i18nKey => messageKey ?? defaultKeyFor(type);

  static String defaultKeyFor(ApiErrorType type) => switch (type) {
    ApiErrorType.network => 'errors.network',
    ApiErrorType.timeout => 'errors.timeout',
    ApiErrorType.cancelled => 'errors.cancelled',
    ApiErrorType.rejected => 'errors.rejected',
    ApiErrorType.unauthorized => 'errors.unauthorized',
    ApiErrorType.forbidden => 'errors.forbidden',
    ApiErrorType.notFound => 'errors.not_found',
    ApiErrorType.conflict => 'errors.conflict',
    ApiErrorType.rateLimited => 'errors.rate_limited',
    ApiErrorType.server => 'errors.server',
    ApiErrorType.sessionExpired => 'errors.session_expired',
    ApiErrorType.loggingOut => 'errors.logging_out',
    ApiErrorType.parse => 'errors.unknown',
    ApiErrorType.unknown => 'errors.unknown',
  };

  /// Wraps anything thrown by the API layer. Never throws.
  factory ApiException.from(Object error, [StackTrace? stackTrace]) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final inner = error.error;
      if (inner is ApiException) return inner;
      return _fromDio(error, stackTrace ?? error.stackTrace);
    }
    if (error is FormatException || error is TypeError) {
      return ApiException(
        ApiErrorType.parse,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return ApiException(
      ApiErrorType.unknown,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static ApiException _fromDio(DioException e, StackTrace? st) {
    final response = e.response;
    final type = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => ApiErrorType.timeout,
      DioExceptionType.cancel => ApiErrorType.cancelled,
      DioExceptionType.connectionError => ApiErrorType.network,
      DioExceptionType.badCertificate => ApiErrorType.network,
      DioExceptionType.badResponse => _typeForStatus(response?.statusCode),
      DioExceptionType.unknown =>
        response == null ? ApiErrorType.network : ApiErrorType.unknown,
    };
    return ApiException(
      type,
      statusCode: response?.statusCode,
      serverMessage: readableServerMessage(response?.data),
      data: response?.data,
      cause: e,
      stackTrace: st,
    );
  }

  static ApiErrorType _typeForStatus(int? status) => switch (status) {
    null => ApiErrorType.unknown,
    400 || 422 => ApiErrorType.rejected,
    401 => ApiErrorType.unauthorized,
    403 => ApiErrorType.forbidden,
    404 => ApiErrorType.notFound,
    408 => ApiErrorType.timeout,
    409 => ApiErrorType.conflict,
    429 => ApiErrorType.rateLimited,
    final s when s >= 500 => ApiErrorType.server,
    _ => ApiErrorType.unknown,
  };

  /// Strapi `{error: {message}}` or custom `{message}`; only kept when it
  /// reads like a sentence (RN `authErrors.js` rule), not an error code.
  static String? readableServerMessage(Object? data) {
    if (data is! Map) return null;
    final error = data['error'];
    final raw = (error is Map ? error['message'] : null) ?? data['message'];
    if (raw is! String) return null;
    final msg = raw.trim();
    if (msg.isEmpty || msg.length > 160 || !msg.contains(RegExp(r'\s'))) {
      return null;
    }
    return msg;
  }

  ApiException copyWith({ApiErrorType? type, String? messageKey}) =>
      ApiException(
        type ?? this.type,
        statusCode: statusCode,
        serverMessage: serverMessage,
        messageKey: messageKey ?? this.messageKey,
        data: data,
        cause: cause,
        stackTrace: stackTrace,
      );

  @override
  String toString() =>
      'ApiException(${type.name}${statusCode != null ? ', $statusCode' : ''}'
      '${serverMessage != null ? ', "$serverMessage"' : ''}'
      '${cause != null && serverMessage == null ? ', $cause' : ''})';
}

extension ApiExceptionMessage on ApiException {
  /// What to show the user. A readable server message wins (it knows best,
  /// e.g. "OTP expired") except for 5xx, which always gets our own copy.
  String localizedMessage(BuildContext context) {
    final server = serverMessage;
    if (server != null && type != ApiErrorType.server) return server;
    return context.t(i18nKey);
  }
}
