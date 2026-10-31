import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../callscreen/call_errors.dart';
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

  /// Host: already on another call when answering.
  static const hostBusy = 'instant_call:errors.host_busy';

  /// Host: the caller can no longer pay for the call.
  static const callerLowBalance = 'instant_call:errors.caller_low_balance';
}

/// The server's `code` on a refusal, read before its English message:
/// Strapi puts the helper's details under `error.details`; older replies
/// carried it at the top or inside an object message.
String? _codeOf(ApiException e) {
  final data = e.data;
  if (data is! Map) return null;
  final error = data['error'];
  final details = error is Map ? error['details'] : null;
  final message = error is Map ? error['message'] : null;
  final code =
      (details is Map ? details['code'] : null) ??
      (error is Map ? error['code'] : null) ??
      (message is Map ? message['code'] : null) ??
      data['code'];
  final s = code == null ? '' : '$code'.trim();
  return s.isEmpty ? null : s;
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

  /// [firstHostId]: a direct call that rolls over — that host (public-user
  /// id) rings first.
  static Future<InitiatedInstantCall> initiate({
    required Object callerId,
    String type = 'voiceCall',
    Object? firstHostId,
  }) async {
    final body = await _guard(
      InstantCallErrorKeys.initiateFailed,
      () => ApiClient.post(
        '/instant-call/initiate',
        data: {'callerId': callerId, 'type': type, 'firstHostId': ?firstHostId},
      ),
    );
    final data = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    // Nobody free is a 200 with `success: false`, not an error status.
    if (data['success'] == false) {
      // The host called is on another call and nobody else is free: the
      // normal "busy" answer.
      if (data['code'] == 'USER_BUSY') {
        throw ApiException(
          ApiErrorType.conflict,
          messageKey: CallErrorKeys.userBusy,
          data: data,
        );
      }
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
      final key = switch (_codeOf(e)) {
        'HOST_BUSY' => InstantCallErrorKeys.hostBusy,
        'CALLER_LOW_BALANCE' => InstantCallErrorKeys.callerLowBalance,
        _ => gone ? InstantCallErrorKeys.taken : null,
      };
      Error.throwWithStackTrace(
        key != null
            ? ApiException(
                e.type,
                statusCode: e.statusCode,
                messageKey: key,
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

  /// Caller: the call record a Talk Now session became once a host
  /// answered, and who answered (`GET /instant-call/status`); null while
  /// nobody has.
  static Future<InstantConnectedCall?> connectedCall(String sessionId) async {
    final body = Strapi.map(
      await ApiClient.get('/instant-call/status/$sessionId'),
    );
    return InstantConnectedCall.tryParse(body);
  }

  /// [connectedCall]'s record id only.
  static Future<String?> connectedCallId(String sessionId) async =>
      (await connectedCall(sessionId))?.callId;

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
    final code = _codeOf(e) ?? '';
    if (code == 'LOW_BALANCE' || m.contains('insufficient balance')) {
      return InstantCallErrorKeys.lowBalance;
    }
    if (code == 'NO_HOSTS' || m.contains('no hosts')) {
      return InstantCallErrorKeys.noHosts;
    }
    if (code == 'ALREADY_ACTIVE' ||
        m.contains('active talk now session') ||
        m.contains('already on a call')) {
      return InstantCallErrorKeys.alreadyActive;
    }
    // Off, staff-only, the type not allowed, or not set up on the server:
    // all "not available" to the user.
    if (const {
          'DISABLED',
          'STAFF_ONLY',
          'TYPE_NOT_ALLOWED',
          'RATE_MISSING',
          'CONFIG_MISSING',
        }.contains(code) ||
        e.type == ApiErrorType.forbidden ||
        m.contains('disabled') ||
        m.contains('not yet available') ||
        m.contains('not enabled') ||
        m.contains('not configured') ||
        m.contains('configuration missing')) {
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
