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

/// After login and on every token refresh (RN CallManager `syncFcmToken`).
/// [userId] defaults to the signed-in user; skipped when signed out.
/// [deviceId] (the stable install id) binds the tokens to this device's
/// session on the backend.
Future<void> syncPushTokens({
  required String fcmToken,
  String? voipToken,
  Object? userId,
  String? deviceId,
}) async {
  final id = userId ?? SessionStore.instance.value.userId;
  if (fcmToken.isEmpty || id == null) return;
  await runBestEffort(
    'fcm token sync',
    () => PushApi.updateFcmToken(id, fcmToken, deviceId: deviceId),
  );
  await registerPushDevice(fcmToken: fcmToken, voipToken: voipToken);
  final voip = J.str(voipToken);
  if (Platform.isIOS && voip != null) {
    await syncVoipToken(voip, userId: id, deviceId: deviceId);
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
