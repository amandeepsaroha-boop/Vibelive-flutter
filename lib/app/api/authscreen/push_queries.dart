import 'dart:async';
import 'dart:io' show Platform;

import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import 'auth_errors.dart';
import 'push_api.dart';

// Push token sync for non-widget callers (the push service). Everything
// here is best effort and never throws: a failed sync must not break login,
// a call or a notification tap.

/// Retry delays of a failed `/fcm-token` save (RN `FCM_SYNC_RETRY_DELAYS_MS`).
const fcmSyncRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 8),
  Duration(seconds: 20),
];

/// After login and on every token refresh (RN CallManager `syncFcmToken`).
/// [userId] defaults to the signed-in user; skipped when signed out.
/// [deviceId] (the stable install id) binds the tokens to this device's
/// session on the backend. True when `/fcm-token` stored the token; when
/// its retries give up, the token is kept in [PushTokens.pendingSync].
Future<bool> syncPushTokens({
  required String fcmToken,
  String? voipToken,
  Object? userId,
  String? deviceId,
}) async {
  final id = userId ?? SessionStore.instance.value.userId;
  if (fcmToken.isEmpty || id == null) return false;
  final stored = await _saveFcmToken(id, fcmToken, deviceId);
  try {
    await PushTokens.savePendingSync(stored ? null : fcmToken);
  } catch (e) {
    Log.w('Push', 'pending marker: $e');
  }
  await registerPushDevice(fcmToken: fcmToken, voipToken: voipToken);
  final voip = J.str(voipToken);
  if (Platform.isIOS && voip != null) {
    await syncVoipToken(voip, userId: id, deviceId: deviceId);
  }
  return stored;
}

/// A dropped save leaves the server with a token the device has replaced
/// (unreachable while installed), so failures worth retrying are retried:
/// no response, 408, 429, 5xx. Never 401/403: the client already refreshed,
/// so the session is going away.
Future<bool> _saveFcmToken(Object id, String token, String? deviceId) async {
  for (var attempt = 0; ; attempt++) {
    try {
      await PushApi.updateFcmToken(id, token, deviceId: deviceId);
      return true;
    } catch (e) {
      final error = ApiException.from(e);
      Log.w('Push', 'fcm token sync failed: $error');
      final retryable =
          error.isTransient ||
          (error.type == ApiErrorType.unknown && error.statusCode == null);
      if (attempt >= fcmSyncRetryDelays.length || !retryable) return false;
      await Future<void>.delayed(fcmSyncRetryDelays[attempt]);
    }
  }
}

/// `PUT /public-users/:id/voip-token` (iOS). `/fcm-token` never stores a
/// VoIP token on the user, so this route is the one PushKit rings use.
Future<void> syncVoipToken(
  String voipToken, {
  Object? userId,
  String? deviceId,
}) async {
  final id = userId ?? SessionStore.instance.value.userId;
  if (voipToken.isEmpty || id == null) return;
  await runBestEffort(
    'voip token sync',
    () => PushApi.updateVoipToken(id, voipToken, deviceId: deviceId),
  );
}

/// Campaign/sequence registry. False when it failed (logged).
Future<bool> registerPushDevice({
  required String fcmToken,
  String? voipToken,
}) async {
  if (fcmToken.isEmpty) return false;
  try {
    await PushApi.registerDevice(fcmToken: fcmToken, voipToken: voipToken);
    return true;
  } on ApiException catch (e) {
    // 403 = the user's role may not call this route (backend permission).
    Log.w('Push', 'device register failed: $e');
    return false;
  }
}

/// Campaigns send `notificationTrackingId`, sequences `trackingId`.
String? pushTrackingIdOf(Map<String, dynamic>? data) =>
    J.str(data?['notificationTrackingId']) ?? J.str(data?['trackingId']);

final _trackedPushEvents = <String>{};

/// Reports a campaign push event; ignores pushes without a tracking id.
/// Fire-and-forget: never awaited by navigation.
void trackPushEvent(PushEvent event, Map<String, dynamic>? data) {
  final trackingId = pushTrackingIdOf(data);
  if (trackingId == null) return;
  // Once per event and push per run: one tap can reach several listeners,
  // and the campaign report must not count it twice.
  if (!_trackedPushEvents.add('${event.name}:$trackingId')) return;
  unawaited(
    runBestEffort(
      'push ${event.name} tracking',
      () => PushApi.trackNotification(
        event: event,
        trackingId: trackingId,
        campaignRecipientId: J.str(data?['campaignRecipientId']),
        deeplink: J.str(data?['deeplink']),
      ),
    ),
  );
}
