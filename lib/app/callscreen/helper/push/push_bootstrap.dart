import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../../../core/utils/log.dart';
import '../../../authscreen/helper/auth_credentials.dart';
import 'fcm_token_registrar.dart';
import 'local_notifier.dart';
import 'notification_channels.dart';
import 'notification_tap_router.dart';
import 'push_background.dart';
import 'push_router.dart';
import 'push_strings.dart';
import 'voip_token_registrar.dart';

/// Firebase + FCM + local notifications wiring (spec_call_native §4.1).
abstract final class PushBootstrap {
  static const _tag = 'PushBootstrap';
  static bool _firebaseReady = false;
  static bool _started = false;

  static bool get firebaseReady => _firebaseReady;

  /// The one Firebase app, initialised once per isolate. The native default
  /// app may already exist (google-services / GoogleService-Info.plist): the
  /// Dart options carry the same API key, so that is no `duplicate-app`.
  static Future<bool> ensureFirebase() async {
    if (Firebase.apps.isNotEmpty) return true;
    try {
      await Firebase.initializeApp(options: AuthCredentials.firebase);
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') return true;
      Log.w(_tag, 'Firebase unavailable: $e');
      return false;
    } catch (e) {
      Log.w(_tag, 'Firebase unavailable: $e');
      return false;
    }
  }

  /// Before `runApp`: Firebase eagerly, and the background handler (it must
  /// be registered from the main isolate before the first message).
  static Future<void> initFirebase() async {
    _firebaseReady = await ensureFirebase();
    if (!_firebaseReady) return;
    try {
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
    } catch (e) {
      Log.w(_tag, 'background handler: $e');
    }
  }

  /// After `runApp`: local notifications, channels, listeners, the one
  /// consumer of the launch tap, then permission → tokens. Safe to call once.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await LocalNotifier.init(
        onTap: (r) => unawaited(NotificationTapRouter.handleLocal(r)),
        onBackgroundTap: notificationTapBackground,
      );
      await NotificationChannels.ensure(LocalNotifier.plugin);
      await PushStrings.ensure();
      if (!_firebaseReady) return;
      final messaging = FirebaseMessaging.instance;
      // Foreground banners are drawn locally (filtered: never over a call,
      // no CallTimer), not by iOS (E54, deviation from RN).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
      FirebaseMessaging.onMessage.listen(
        (m) => unawaited(PushRouter.handleForeground(m)),
      );
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => unawaited(NotificationTapRouter.handleRemote(m)),
      );
      unawaited(_launchTap());
      unawaited(_permissionThenTokens());
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }

  /// The read-once launch taps, consumed HERE only (RN's two read-once
  /// getters swallowed each other's taps, E48).
  static Future<void> _launchTap() async {
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        await NotificationTapRouter.handleRemote(initial);
        return;
      }
      final local = await LocalNotifier.launchEnvelope();
      if (local != null) await NotificationTapRouter.handle(local);
    } catch (e) {
      Log.w(_tag, 'launch tap: $e');
    }
  }

  static Future<void> _permissionThenTokens() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (e) {
      Log.w(_tag, 'permission: $e');
    }
    await FcmTokenRegistrar.start();
    if (Platform.isIOS) await VoipTokenRegistrar.refresh();
  }
}
