import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../../core/storage/app_prefs.dart';
import '../native/call_background_isolate.dart';
import 'push_bootstrap.dart';
import 'push_router.dart';

/// FCM data message while the app is killed or backgrounded, in its own
/// isolate (spec_call_native §4.5). Registered in `main()` before `runApp`.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushBootstrap.ensureFirebase();
  await AppPrefs.init();
  await PushRouter.handleBackground(
    message,
    prepare: CallBackground.ensureReady,
  );
}

/// A notification ACTION tapped while the app is not running (Android). We
/// add no action buttons, so this only has to exist: plain taps relaunch the
/// app and are replayed from `getNotificationAppLaunchDetails`.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {}
