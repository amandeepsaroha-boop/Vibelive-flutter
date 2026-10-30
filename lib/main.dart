import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:fquery/fquery.dart';

import 'app/authscreen/helper/deep_links.dart';
import 'app/banner/session_issue_host.dart';
import 'app/callscreen/call/call_overlay_host.dart';
import 'app/callscreen/call/capture_shield.dart';
import 'app/callscreen/call_flow.dart';
import 'app/callscreen/helper/push/push_bootstrap.dart';
import 'app/splashscreen/launch_logo.dart';
import 'app/splashscreen/splash_screen.dart';
import 'app/update/update_notice.dart';
import 'core/analytics/analytics.dart';
import 'core/analytics/analytics_identity.dart';
import 'core/analytics/screen_tracker.dart';
import 'core/app_scope.dart';
import 'core/error/app_error_handler.dart';
import 'core/i18n/i18n.dart';
import 'core/network/network_status.dart';
import 'core/query/query_client.dart';
import 'core/router/app_router.dart';
import 'core/session/legacy_session_migration.dart';
import 'core/session/session_store.dart';
import 'core/storage/app_prefs.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Call listeners FIRST, before anything awaits (a VoIP / CallKit launch
  // delivers its accept and push events right away; spec §2.7).
  CallFlow.attach();
  SplashScreen.holdFirstFrame();
  AppErrorHandler.init();
  // Auto-rotate off (also locked in Info.plist / AndroidManifest).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await AppPrefs.init();
  // RN → Flutter update: continue the RN session (once, before restore).
  await LegacySessionMigration.run();
  await SessionStore.instance.restore();
  // Firebase eagerly + the FCM background handler (before runApp).
  await PushBootstrap.initFirebase();
  // Firebase Analytics + Meta App Events: user identity, every screen.
  unawaited(Analytics.init());
  AnalyticsIdentity.attach();
  ScreenTracker.attach(appRouter);
  // CallPlatform, native config, session hooks, cold-start reconcile.
  await CallFlow.init();
  DeepLinks.instance.init();
  unawaited(NetworkStatus.instance.init());

  runApp(
    VibeLiveApp(
      themeController: ThemeController.load(),
      localeController: LocaleController.load(),
    ),
  );
  // Call logic's reconcile (parked accept / navigation / declines), then
  // the cold-start resume.
  unawaited(CallFlow.afterRunApp());
  // Local notifications, onMessage / taps, permission → tokens.
  unawaited(PushBootstrap.start());
}

class VibeLiveApp extends StatelessWidget {
  const VibeLiveApp({
    super.key,
    required this.themeController,
    required this.localeController,
  });

  final ThemeController themeController;
  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      theme: themeController,
      locale: localeController,
      child: CacheProvider(
        cache: queryCache,
        child: ListenableBuilder(
          listenable: Listenable.merge([themeController, localeController]),
          builder: (context, _) => MaterialApp.router(
            title: 'Vibe Live',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeController.value,
            // No 200 ms ThemeData lerp: it rebuilt every `context.colors`
            // reader in the app on each of its ~25 frames, while the app's
            // own colors (VibeColors.lerp) don't fade, they snap halfway.
            themeAnimationStyle: AnimationStyle.noAnimation,
            routerConfig: appRouter,
            scaffoldMessengerKey: scaffoldMessengerKey,
            locale: localeController.value,
            supportedLocales: AppI18n.supportedLocales,
            localizationsDelegates: [
              AppI18n.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            builder: (context, child) {
              Scale.update(MediaQuery.sizeOf(context));
              // The update notice sits under the call overlay: never over a call.
              // So does "Server unreachable" (a session that can't refresh;
              // the app never signs anyone out on its own).
              // The capture shield sits over everything: a recorded video call
              // shows the logo, not the call.
              return CaptureShield(
                child: CallOverlayHost(
                  child: SessionIssueHost(
                    child: UpdateNoticeHost(
                      // The splash logo's flight into the first screen.
                      child: LaunchLogoLayer(
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
