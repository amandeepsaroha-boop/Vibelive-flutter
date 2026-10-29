import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'instant_call_models.dart';

abstract final class InstantCallErrorKeys {
  static const initiateFailed = 'instant_call:errors.initiate_failed';
  static const cancelFailed = 'instant_call:errors.cancel_failed';
  static const invalidResponse = 'instant_call:errors.invalid_response';
  static const noHosts = 'instant_call:errors.no_hosts';
  static const disabled = 'instant_call:errors.disabled';
}

abstract final class InstantCallApi {
  static Future<InitiatedInstantCall> initiate({
    required Object callerId,
    String type = 'voiceCall',
  }) async {
    final body = await _guard(
      InstantCallErrorKeys.initiateFailed,
      () => ApiClient.post(
        '/instant-call/initiate',
        data: {'callerId': callerId, 'type': type},
      ),
    );
    final data = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    final result = InitiatedInstantCall.tryParse(data);
    if (result == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: InstantCallErrorKeys.invalidResponse,
      );
    }
    return result;
  }

  static Future<void> cancel(String sessionId) async {
    await _guard(
      InstantCallErrorKeys.cancelFailed,
      () => ApiClient.post(
        '/instant-call/cancel',
        data: {'sessionId': sessionId},
      ),
    );
  }
}

Future<T> _guard<T>(String key, Future<T> Function() body) async {
  try {
    return await body();
  } on ApiException catch (e, st) {
    final tagged = e.messageKey != null ? e : e.copyWith(messageKey: key);
    Error.throwWithStackTrace(tagged, st);
  }
}
