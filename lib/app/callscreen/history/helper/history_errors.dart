import '../../../../core/network/api_exception.dart';

/// Alert copy of the Logs tab's failed actions (RN explore `Alert.alert`
/// calls). RN never showed the server's text for a review or report, and
/// always showed it for a nudge.
abstract final class HistoryErrors {
  /// RN title of the review / report / nudge failure alerts: "Error".
  static const title = 'call:history.error_title';

  /// RN title of a failed profile lookup: "Profile".
  static const profileTitle = 'call:history.profile_title';

  /// [key] for every answer the server gave (RN "Failed to submit review." /
  /// "Failed to submit report."). No answer at all (offline, timeout, the
  /// session gone) keeps the app's own, more useful copy.
  static ApiException relabel(ApiException e, String key) => _noAnswer(e)
      ? e
      : ApiException(
          e.type,
          statusCode: e.statusCode,
          messageKey: key,
          data: e.data,
          cause: e.cause,
          stackTrace: e.stackTrace,
        );

  /// RN nudge: `data.message || data.error.message || 'Failed to send
  /// ping.'`. The server's text as sent (the 3-a-day limit, the cooldown),
  /// whatever the status, 5xx included.
  static ApiException ping(ApiException e, String fallbackKey) {
    final body = e.data;
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final error = body is Map ? body['error'] : null;
    final server = body is Map
        ? text(body['message']) ?? text(error is Map ? error['message'] : null)
        : null;
    if (server == null) return relabel(e, fallbackKey);
    // `localizedMessage` drops a 5xx server message: carry it as a refusal.
    return ApiException(
      ApiErrorType.rejected,
      statusCode: e.statusCode,
      serverMessage: server,
      data: e.data,
      cause: e.cause,
      stackTrace: e.stackTrace,
    );
  }

  static bool _noAnswer(ApiException e) => switch (e.type) {
    ApiErrorType.network ||
    ApiErrorType.timeout ||
    ApiErrorType.cancelled ||
    ApiErrorType.sessionExpired ||
    ApiErrorType.loggingOut => true,
    _ => false,
  };
}
