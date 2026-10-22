import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../../core/network/device_info.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/authscreen/push_api.dart';
import '../../../api/authscreen/push_queries.dart';

// firebase_messaging 17 deprecates the registration-token API in favour of
// FID direct-send (`register` / `onRegistered`). The backend sends with
// firebase-admin to registration tokens, so the token API stays:
// ignore_for_file: deprecated_member_use

/// Keeps this device's FCM token stored (login reads it) and on the backend
/// (`/fcm-token` with `deviceId`, the orchestrator registry, and the VoIP
/// token alongside on iOS). Never throws.
abstract final class FcmTokenRegistrar {
  static const _tag = 'FcmToken';
  static StreamSubscription<String>? _refresh;
  static String? _lastSynced;
  static Future<void>? _syncing;

  /// Startup: listen for rotations FIRST (on iOS the first token often
  /// arrives on the stream), then fetch, store and sync when signed in.
  static Future<void> start() async {
    if (Firebase.apps.isEmpty) return;
    _refresh ??= FirebaseMessaging.instance.onTokenRefresh.listen((
      token,
    ) async {
      if (token.isEmpty) return;
      await PushTokens.saveFcm(token);
      await syncIfSignedIn();
    }, onError: (Object e) => Log.w(_tag, 'refresh stream: $e'));
    final token = await fetchToken();
    if (token != null) {
      await PushTokens.saveFcm(token);
      await syncIfSignedIn();
    }
  }

  /// `getToken()` throws `apns-token-not-set` on iOS until APNs answered:
  /// wait up to 10 s (20 × 500 ms) for it (CE).
  static Future<String?> fetchToken() async {
    if (Firebase.apps.isEmpty) return null;
    try {
      final messaging = FirebaseMessaging.instance;
      if (Platform.isIOS) {
        for (var i = 0; i < 20; i++) {
          if (await messaging.getAPNSToken() != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      final token = await messaging.getToken();
      return token == null || token.isEmpty ? null : token;
    } catch (e) {
      Log.w(_tag, 'getToken failed: $e');
      return null;
    }
  }

  /// Sends the stored tokens for the signed-in user (once per change).
  static Future<void> syncIfSignedIn({bool force = false}) =>
      _syncing ??= _sync(force).whenComplete(() => _syncing = null);

  static Future<void> _sync(bool force) async {
    final session = SessionStore.instance.value;
    final fcm = PushTokens.fcm;
    final userId = session.userId;
    if (!session.isAuthenticated || fcm == null || userId == null) return;
    final voip = PushTokens.voip;
    final key = '$userId|$fcm|${voip ?? ''}';
    if (!force && key == _lastSynced) return;
    try {
      final deviceId = (await DeviceInfo.get())['deviceId']?.toString();
      await syncPushTokens(
        fcmToken: fcm,
        voipToken: voip,
        userId: userId,
        deviceId: deviceId,
      );
      _lastSynced = key;
    } catch (e) {
      Log.w(_tag, 'sync failed: $e');
    }
  }

  /// Logout: delete the device token, then fetch and store a fresh one.
  /// Without the refetch a login without a restart registered the dead
  /// token (CE, E51).
  static Future<void> renewAfterSignOut() async {
    _lastSynced = null;
    await PushTokens.saveFcm(null);
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      Log.w(_tag, 'deleteToken failed: $e');
    }
    final fresh = await fetchToken();
    if (fresh != null) await PushTokens.saveFcm(fresh);
  }
}
