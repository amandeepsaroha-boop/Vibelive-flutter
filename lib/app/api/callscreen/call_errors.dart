import '../../../core/network/api_exception.dart';

/// i18n keys (namespace `call`) for failures the call API raises or relabels.
abstract final class CallErrorKeys {
  static const userBusy = 'call:errors.user_busy';
  static const invalidResponse = 'call:errors.invalid_response';
  static const initiateFailed = 'call:errors.initiate_failed';
  static const missingParticipants = 'call:errors.missing_participants';
  static const reviewEmpty = 'call:errors.review_empty';
  static const expertUnresolved = 'call:errors.expert_unresolved';
  static const reviewFailed = 'call:errors.review_failed';
  static const pingFailed = 'call:errors.ping_failed';
}

/// Runs [body] and relabels its failure with [key] (see
/// [CallApiExceptionX.withFallbackKey]).
Future<T> withCallFallback<T>(String key, Future<T> Function() body) async {
  try {
    return await body();
  } on ApiException catch (e, st) {
    Error.throwWithStackTrace(e.withFallbackKey(key), st);
  }
}

/// Backend answers the RN call screens deliberately ignored.
extension CallApiExceptionX on ApiException {
  /// `/initiateCall` answered "busy": the receiver is on another call.
  bool get isUserBusy => messageKey == CallErrorKeys.userBusy;

  /// Ringing ack for a call that already left the pending state.
  bool get isBenignRingingAck =>
      statusCode == 409 && _message.contains('not in pending state');

  /// Decline for a call the backend already closed or never had.
  bool get isBenignDecline =>
      statusCode == 404 ||
      (statusCode == 400 &&
          (_message.contains('already') || _message.contains('not found')));

  /// Call end that lost the race against the other side's end.
  bool get isCallAlreadyEnded =>
      _message.contains('call has been ended already') ||
      ((statusCode == 400 || statusCode == 404 || statusCode == 409) &&
          _message.contains('already'));

  /// Feature copy for a failed action (RN alert fallback). A readable server
  /// message still wins in `localizedMessage`; connectivity and session
  /// errors keep their own, more useful copy.
  ApiException withFallbackKey(String key) =>
      messageKey != null || _keepsOwnCopy ? this : copyWith(messageKey: key);

  bool get _keepsOwnCopy => switch (type) {
    ApiErrorType.network ||
    ApiErrorType.timeout ||
    ApiErrorType.cancelled ||
    ApiErrorType.rateLimited ||
    ApiErrorType.unauthorized ||
    ApiErrorType.sessionExpired ||
    ApiErrorType.loggingOut => true,
    _ => false,
  };

  /// Raw backend message (`message` / `error.message`), lower-cased. Not
  /// filtered for readability like [serverMessage]: codes count here.
  String get _message {
    final body = data;
    final parts = <Object?>[serverMessage];
    if (body is Map) {
      final error = body['error'];
      parts
        ..add(body['message'])
        ..add(error is Map ? error['message'] : null);
    }
    return parts.whereType<String>().join(' ').toLowerCase();
  }
}
