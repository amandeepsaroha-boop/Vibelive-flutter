import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'instant_call_models.dart';

abstract final class InstantCallErrorKeys {
  static const initiateFailed = 'instant_call:errors.initiate_failed';
  static const cancelFailed = 'instant_call:errors.cancel_failed';
  static const invalidResponse = 'instant_call:errors.invalid_response';
  static const noHosts = 'instant_call:errors.no_hosts';
  static const disabled = 'instant_call:errors.disabled';
  static const lowBalance = 'instant_call:errors.low_balance';
  static const alreadyActive = 'instant_call:errors.already_active';
  static const taken = 'instant_call:errors.taken';
}

abstract final class InstantCallApi {
  /// `GET /instant-call/config`: whether Talk Now is on for this user (off
  /// when unset, staff-only for someone else, or unreadable), and how.
  static Future<InstantCallConfig> fetchConfig() async {
    try {
      final body = Strapi.map(await ApiClient.get('/instant-call/config'));
      return InstantCallConfig.fromJson(body ?? const {});
    } on ApiException {
      return InstantCallConfig.off;
    }
  }

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
    // Nobody free is a 200 with `success: false`, not an error status.
    if (data['success'] == false) {
      throw ApiException(
        ApiErrorType.rejected,
        messageKey: data['code'] == 'NO_HOSTS'
            ? InstantCallErrorKeys.noHosts
            : InstantCallErrorKeys.initiateFailed,
        data: data,
      );
    }
    final result = InitiatedInstantCall.tryParse(data);
    if (result == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: InstantCallErrorKeys.invalidResponse,
      );
    }
    return result;
  }

  /// Host: answer a Talk Now ring. The backend creates the call record
  /// (billed at the Talk Now rates) and stops the other rings. Idempotent
  /// for the host who already has the call (native + app may both send it).
  /// Throws [ApiException] with [InstantCallErrorKeys.taken] when the call
  /// is no longer this host's to take (cancelled, another host, too late).
  static Future<InstantHostAccept> hostAccept(String sessionId) async {
    final dynamic body;
    try {
      body = await ApiClient.post(
        '/instant-call/host-accept',
        data: {'sessionId': sessionId},
      );
    } on ApiException catch (e, st) {
      final gone =
          e.type == ApiErrorType.rejected ||
          e.type == ApiErrorType.notFound ||
          e.type == ApiErrorType.conflict;
      Error.throwWithStackTrace(
        gone
            ? ApiException(
                e.type,
                statusCode: e.statusCode,
                messageKey: InstantCallErrorKeys.taken,
                data: e.data,
              )
            : e,
        st,
      );
    }
    final result = InstantHostAccept.tryParse(
      body is Map ? Map<String, dynamic>.from(body) : const {},
    );
    if (result == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: InstantCallErrorKeys.invalidResponse,
      );
    }
    return result;
  }

  /// Host: decline a Talk Now ring, so the server rings the next host at
  /// once (instead of after the ring window). Never throws: the server's
  /// own timer moves on anyway.
  static Future<void> hostDecline(String sessionId) async {
    try {
      await ApiClient.post(
        '/instant-call/host-decline',
        data: {'sessionId': sessionId},
      );
    } catch (_) {}
  }

  /// Caller: the call record a connected Talk Now session became
  /// (`GET /instant-call/status`), or null.
  static Future<String?> connectedCallId(String sessionId) async {
    final body = Strapi.map(
      await ApiClient.get('/instant-call/status/$sessionId'),
    );
    final call = body?['connectedCall'];
    return call is Map ? J.str(call['id']) : null;
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

  /// The server's known refusals, in the user's language instead of its
  /// English message; null for anything else.
  static String? knownErrorKey(ApiException e) {
    final m = (e.serverMessage ?? '').toLowerCase();
    final code = e.data is Map ? '${(e.data! as Map)['code'] ?? ''}' : '';
    if (code == 'LOW_BALANCE' || m.contains('insufficient balance')) {
      return InstantCallErrorKeys.lowBalance;
    }
    if (code == 'NO_HOSTS' || m.contains('no hosts')) {
      return InstantCallErrorKeys.noHosts;
    }
    if (m.contains('active talk now session') ||
        m.contains('already on a call')) {
      return InstantCallErrorKeys.alreadyActive;
    }
    if (e.type == ApiErrorType.forbidden ||
        m.contains('disabled') ||
        m.contains('not yet available') ||
        m.contains('not enabled')) {
      return InstantCallErrorKeys.disabled;
    }
    return null;
  }
}

Future<T> _guard<T>(String key, Future<T> Function() body) async {
  try {
    return await body();
  } on ApiException catch (e, st) {
    final known = InstantCallApi.knownErrorKey(e);
    final tagged = known != null
        // Our copy, translated: drop the server's English.
        ? ApiException(
            e.type == ApiErrorType.server ? ApiErrorType.rejected : e.type,
            statusCode: e.statusCode,
            messageKey: known,
            data: e.data,
            cause: e.cause,
          )
        : (e.messageKey != null ? e : e.copyWith(messageKey: key));
    Error.throwWithStackTrace(tagged, st);
  }
}
