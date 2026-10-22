import 'dart:io' show Platform;

import '../../../core/network/api_client.dart';
import '../../../core/network/device_info.dart';
import '../../../core/network/strapi.dart';
import '../../../core/storage/app_prefs.dart';

/// Campaign push lifecycle events the orchestrator counts.
enum PushEvent { delivered, opened, clicked }

/// Push device registries. Two of them: the App Notification Orchestrator
/// (campaigns and sequences) and the per-user tokens calling still uses.
/// The native token sources (FCM, PushKit) are not part of the API layer.
abstract final class PushApi {
  static const _orchestrator = '/app-notification-orchestrator';
  static const unregisterTimeout = Duration(seconds: 5);
  static const trackTimeout = Duration(seconds: 10);

  static Future<void> registerDevice({
    required String fcmToken,
    String? voipToken,
  }) async {
    await ApiClient.post(
      '$_orchestrator/devices/register',
      data: _deviceBody(fcmToken, voipToken),
    );
  }

  /// Logout. [accessToken] is the user's token captured before the session
  /// is wiped; sent as-is so a 401 cannot start a refresh.
  static Future<void> unregisterDevice({
    required String fcmToken,
    String? voipToken,
    String? accessToken,
  }) async {
    final token = J.str(accessToken);
    await ApiClient.post(
      '$_orchestrator/devices/unregister',
      data: _deviceBody(fcmToken, voipToken),
      headers: token == null ? null : {'Authorization': 'Bearer $token'},
      skipAuth: token != null,
      timeout: unregisterTimeout,
    );
  }

  /// Campaign/sequence analytics for one push.
  static Future<void> trackNotification({
    required PushEvent event,
    required String trackingId,
    String? campaignRecipientId,
    String? deeplink,
  }) async {
    final device = await DeviceInfo.get();
    await ApiClient.post(
      '$_orchestrator/notifications/track',
      data: {
        'eventType': event.name,
        'trackingId': trackingId,
        'campaignRecipientId': ?J.str(campaignRecipientId),
        'metadata': {
          'deeplink': J.str(deeplink),
          'platform': DeviceInfo.platform,
          'appVersion': device['appVersion'],
        },
      },
      timeout: trackTimeout,
    );
  }

  /// Per-user registry calling rings through. It stores `firebaseTokens`
  /// only and ignores a VoIP token: that one has [updateVoipToken].
  ///
  /// [deviceId] (the stable install id) makes the backend bind the token to
  /// THIS device's session instead of "the newest session".
  static Future<void> updateFcmToken(
    Object userId,
    String fcmToken, {
    String? deviceId,
  }) async {
    await ApiClient.put(
      '/public-users/${_segment(userId)}/fcm-token',
      data: {'firebaseTokens': fcmToken, 'deviceId': ?J.str(deviceId)},
    );
  }

  /// Logout: empties the user's push tokens (all of them, as RN did).
  static Future<void> clearPushTokens(Object userId) async {
    await ApiClient.put(
      '/public-users/${_segment(userId)}/fcm-token',
      data: {'firebaseTokens': <String>[], 'voipToken': null},
    );
  }

  /// iOS PushKit token, used for CallKit rings.
  static Future<void> updateVoipToken(
    Object userId,
    String voipToken, {
    String? deviceId,
  }) async {
    await ApiClient.put(
      '/public-users/${_segment(userId)}/voip-token',
      data: {'voipToken': voipToken, 'deviceId': ?J.str(deviceId)},
    );
  }

  /// Expert presence probe answer (`EXPERT_PRESENCE_PROBE`, CE). The backend
  /// answers 403 for non-experts.
  static Future<void> expertHeartbeat({required String via}) async {
    await ApiClient.post(
      '/expert-profiles/heartbeat',
      data: {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'platform': DeviceInfo.platform,
        'via': via,
      },
      timeout: trackTimeout,
    );
  }

  static JsonMap _deviceBody(String fcmToken, String? voipToken) => {
    'fcmToken': fcmToken,
    'voipToken': ?J.str(voipToken),
  };

  static String _segment(Object id) => Uri.encodeComponent('$id');
}

/// This install's push tokens, kept where the login request and the logout
/// cleanup read them. Written by the push layer (FCM registrar, PushKit
/// reader); the API layer never talks to a plugin itself.
abstract final class PushTokens {
  static const fcmKey = 'fcm_token';
  static const voipKey = 'voip_token';

  /// Login retries the PushKit read this often, this far apart (RN
  /// `LoginScreen`: PushKit often issues the token after the login request).
  static const voipLoginAttempts = 3;
  static const voipLoginDelay = Duration(milliseconds: 1500);

  /// Reads the current PushKit token from the plugin (iOS). Installed by the
  /// push layer at boot; null in tests and on Android.
  static Future<String?> Function()? voipReader;

  static String? get fcm => J.str(AppPrefs.getString(fcmKey));
  static String? get voip => J.str(AppPrefs.getString(voipKey));

  static Future<void> saveFcm(String? token) => _save(fcmKey, token);
  static Future<void> saveVoip(String? token) => _save(voipKey, token);

  /// The VoIP token for a login request: the stored one, else up to
  /// [voipLoginAttempts] reads [voipLoginDelay] apart. iOS only.
  static Future<String?> voipForLogin() async {
    final stored = voip;
    final reader = voipReader;
    if (stored != null || reader == null || !Platform.isIOS) return stored;
    for (var i = 0; i < voipLoginAttempts; i++) {
      if (i > 0) await Future<void>.delayed(voipLoginDelay);
      try {
        final token = J.str(await reader());
        if (token != null) {
          await saveVoip(token);
          return token;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<void> _save(String key, String? token) {
    final value = J.str(token);
    return value == null
        ? AppPrefs.remove(key)
        : AppPrefs.setString(key, value);
  }
}
