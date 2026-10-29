import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../../core/config/env.dart';
import '../../core/network/device_info.dart';
import '../../core/session/session_store.dart';
import '../../core/storage/app_prefs.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/log.dart';
import 'helper/call_analytics.dart';
import 'helper/call_actions.dart';
import 'helper/call_controller.dart';
import 'helper/call_platform.dart';
import 'helper/call_signals.dart';
import 'helper/native/call_background_isolate.dart';
import 'helper/native/call_isolate_bridge.dart';
import 'helper/native/call_permission_primer.dart';
import 'helper/native/callkit_service.dart';
import 'helper/native/incoming_call_intents.dart';
import 'helper/native/native_call_bridge.dart';
import 'helper/native/native_call_events.dart';
import 'helper/native/ring_promoter.dart';
import 'helper/native/vibe_call_platform.dart';
import 'helper/push/fcm_token_registrar.dart';
import 'helper/push/host_heartbeat.dart';
import 'helper/push/local_notifier.dart';
import 'helper/push/milestone_queue.dart';
import 'helper/push/voip_token_registrar.dart';

/// Front door of the native + push call layer: boot wiring (listeners,
/// `CallPlatform`, reconcile), the session hooks (token sync, logout
/// cleanup) and app-resume handling. Every step is guarded: a failure here
/// never blocks boot.
abstract final class CallFlow {
  static const _tag = 'CallFlow';
  static const _fsiPromptedKey = 'push_fsi_prompted_v1';

  static bool _initialised = false;
  static AppLifecycleListener? _lifecycle;
  static bool _signedIn = false;
  static Future<void>? _reconciled;
  static DateTime? _lastResume;
  static bool _wasBackgrounded = false;

  static bool get isOnCall => CallController.instance.isOnCall;

  /// Synchronous, first thing in `main()`: the plugin / bridge listeners
  /// attach before anything awaits Agora, Firebase or the network (§2.7).
  static void attach() {
    try {
      // Before `SessionStore.restore`: a locked VoIP boot must not wipe a
      // session it cannot read (I10).
      SessionStore.protectedDataAvailable =
          NativeCallBridge.isProtectedDataAvailable;
      NativeCallEvents.attach();
      // Call events (Firebase + Meta) from the call's phase changes.
      CallAnalytics.attach();
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }

  /// After prefs and the session are restored, before `runApp`.
  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    await _step('platform', () async {
      CallPlatform.instance = const VibeCallPlatform();
      TokenStorage.onAccessTokenChanged = (token) =>
          unawaited(NativeCallBridge.setAuthToken(token));
    });
    await _step('native config', _configureNative);
    await _step('token mirror', () async {
      final token = await TokenStorage.instance.readAccessToken();
      if (token != null && token.isNotEmpty) {
        await NativeCallBridge.setAuthToken(token);
      }
    });
    await _step('isolate bridge', () async {
      CallIsolateBridge.host((kind, callId) {
        if (kind == CallIsolateBridge.kindEnded) {
          unawaited(CallSignals.onEnded(callId));
        } else if (kind == CallIsolateBridge.kindAnsweredElsewhere) {
          CallSignals.onAnsweredElsewhere(callId);
        }
      });
    });
    // Android: a Decline on a killed app's notification must reach an
    // engine (E40); registered here and in the FCM background isolate.
    await _step(
      'callkit background handler',
      () => CallKitService.registerBackgroundHandler(onCallKitBackgroundEvent),
    );
    await _step('voip token reader', VoipTokenRegistrar.init);
    _signedIn = SessionStore.instance.value.isAuthenticated;
    SessionStore.instance.signedIn.addListener(_onSessionChanged);
    // U3: a call outlives no sign-out; its Callend needs the token.
    SessionStore.beforeSignOut = _beforeSignOut;
    HostHeartbeat.attach();
    _lifecycle ??= AppLifecycleListener(
      onResume: () => unawaited(_resumed()),
      // I4: an in-app ring goes to CallKit when the app leaves the screen.
      onHide: _backgrounded,
      onPause: _backgrounded,
    );
    // Reconcile without holding the first frame: an accept it replays may
    // wait for the audio session or the router.
    _reconciled = _reconcile();
    if (_signedIn) unawaited(_afterSignIn(startup: true));
  }

  static Future<void> _reconcile() async {
    await _step('reconcile', NativeCallEvents.reconcile);
    NativeCallEvents.open();
    await _step('notification intents', IncomingCallIntents.init);
  }

  /// Once, after `runApp`: the call logic's own reconcile (parked accept
  /// from the Android background isolate, parked navigation, decline
  /// replay), then the cold-start resume when the app is in front (a VoIP
  /// background launch resumes later, through the lifecycle listener).
  static Future<void> afterRunApp() async {
    await _reconciled;
    Log.w(_tag, 'native reconcile done, logic reconcile next');
    await _step('logic reconcile', CallSignals.reconcile);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await _resumed();
    }
  }

  static void _backgrounded() {
    _wasBackgrounded = true;
    HostHeartbeat.stop();
    unawaited(RingPromoter.onBackgrounded());
  }

  /// Every resume, the cold start included (once: the listener and
  /// [afterRunApp] can both see the first one).
  static Future<void> _resumed() async {
    final now = DateTime.now();
    final last = _lastResume;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastResume = now;
    // A host in the app is online now, not at the next interval.
    HostHeartbeat.sync();
    await _step('resume', NativeCallEvents.onResumed);
    // A sign-in that happened while the app was not in front.
    if (_signedIn) {
      await _step('call permissions', CallPermissionPrimer.primeIfExpert);
    }
    // Back from the background only: the cold start already fetches and
    // syncs the token (PushBootstrap).
    final returning = _wasBackgrounded;
    _wasBackgrounded = false;
    if (returning && _signedIn) {
      await _step('fcm republish', FcmTokenRegistrar.republish);
    }
  }

  /// What native HTTP needs while Dart may not run (§2.6): at boot and
  /// after every login.
  static Future<void> _configureNative() async {
    if (!Platform.isIOS) return;
    final device = await DeviceInfo.get();
    await NativeCallBridge.configure(
      apiBaseUrl: Env.apiBaseUrl,
      appPlatform: Env.appPlatform,
      defaultToken: Env.defaultApiToken.isEmpty ? null : Env.defaultApiToken,
      deviceId: device['deviceId']?.toString(),
      userId: SessionStore.instance.value.userId?.toString(),
    );
  }

  static void _onSessionChanged() {
    final now = SessionStore.instance.value.isAuthenticated;
    if (now == _signedIn) return;
    _signedIn = now;
    unawaited(now ? _afterSignIn() : _afterSignOut());
  }

  /// Login, or a signed-in start: native config, token sync (FCM with
  /// deviceId, VoIP, orchestrator), missed milestones, Android call UI
  /// permissions once.
  static Future<void> _afterSignIn({bool startup = false}) async {
    await _step('native config', _configureNative);
    if (!startup) {
      await _step(
        'fcm sync',
        () => FcmTokenRegistrar.syncIfSignedIn(force: true),
      );
    }
    await _step('voip sync', () async {
      await VoipTokenRegistrar.refresh(sync: false);
      await VoipTokenRegistrar.syncNow();
    });
    final docId = SessionStore.instance.value.userDocumentId;
    if (docId != null) {
      await _step('milestones', () => MilestoneQueue.fetchMissed(docId));
    }
    if (Platform.isAndroid && AppPrefs.getString(_fsiPromptedKey) == null) {
      await AppPrefs.setString(_fsiPromptedKey, '1');
      await _step(
        'call UI permissions',
        CallKitService.requestAndroidCallUiPermissions,
      );
    }
    // Experts answer from the lock screen, where no prompt can show (A2).
    await _step('call permissions', CallPermissionPrimer.primeIfExpert);
  }

  /// Sign-out while a call exists (U3): hang up / decline it and wait for
  /// its Callend while the token still exists, before the router sends the
  /// user to login with the mic live and the call billing.
  static Future<void> _beforeSignOut() async {
    if (!CallController.instance.isOnCall) return;
    await CallActions.endForSignOut();
  }

  /// Logout cleanup: every system call ended, the native token cleared,
  /// our notifications gone, the FCM token kept for the next login. The
  /// server-side unregister already ran (it needs the user's token).
  static Future<void> _afterSignOut() async {
    await _step('native token', () => NativeCallBridge.setAuthToken(null));
    await _step('end calls', CallKitService.endAll);
    await _step('notifications', LocalNotifier.cancelAll);
    MilestoneQueue.clear();
    await _step('fcm renew', FcmTokenRegistrar.renewAfterSignOut);
  }

  static Future<void> _step(String what, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, st) {
      Log.e('$_tag $what', e, st);
    }
  }
}
