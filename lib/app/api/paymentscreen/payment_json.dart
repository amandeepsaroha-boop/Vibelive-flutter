import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';

/// Response and error normalization shared by the payment API files.

/// Body of a custom (non-entity) payment endpoint: RN `res.data.data ||
/// res.data`. Unlike [Strapi.node] it never descends into a nested `data`
/// field, which these payloads use for their own content.
JsonMap paymentData(dynamic body) {
  final inner = body is Map ? body['data'] : null;
  final node = inner is Map ? inner : body;
  return node is Map ? Map<String, dynamic>.from(node) : <String, dynamic>{};
}

/// Rows of a Strapi collection response. A body without a `data` list is
/// malformed: failing beats showing an empty wallet or history.
List<JsonMap> paymentRows(dynamic body) {
  final data = body is Map ? body['data'] : null;
  if (data is! List) throw const ApiException(ApiErrorType.parse);
  return [for (final row in data) ?Strapi.map(row)];
}

/// Readable message from a payload that reported failure with HTTP 200
/// (`{status: "error", error: {message}}`, `{message}` or `{error: "…"}`).
String? paymentMessage(JsonMap payload) {
  final error = payload['error'];
  return ApiException.readableServerMessage(payload) ??
      (error is String
          ? ApiException.readableServerMessage({'message': error})
          : null);
}

/// Gives [e] the payment-specific [messageKey], except when its own copy is
/// more useful (offline, timeout, session expired…). Status code and server
/// message are kept, so a 409 can still re-route the gateway.
ApiException paymentError(ApiException e, String messageKey) {
  if (e.messageKey != null) return e;
  return switch (e.type) {
    ApiErrorType.network ||
    ApiErrorType.timeout ||
    ApiErrorType.cancelled ||
    ApiErrorType.unauthorized ||
    ApiErrorType.sessionExpired ||
    ApiErrorType.loggingOut ||
    ApiErrorType.rateLimited => e,
    _ => e.copyWith(messageKey: messageKey),
  };
}

/// RN `/^\d+$/` check: numeric ids filter on `id`, anything else on
/// `documentId`.
String userFilterField(String userId) =>
    RegExp(r'^\d+$').hasMatch(userId) ? 'id' : 'documentId';
