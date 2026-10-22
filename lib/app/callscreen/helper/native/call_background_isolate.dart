import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

import '../../../../core/session/session_store.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../../core/utils/log.dart';
import '../call_platform.dart';
import '../call_runtime.dart';
import '../call_signals.dart';
import 'call_isolate_bridge.dart';
import 'callkit_service.dart';
import 'headless_call_end.dart';
import 'native_call_marks.dart';
import 'vibe_call_platform.dart';

/// What the call layer needs in an isolate with no UI (Android): the FCM
/// background isolate rings; the CallKit background isolate receives what
/// the user then did on the notification.
abstract final class CallBackground {
  static bool _ready = false;

  /// FCM background isolate, before handling a push. The CallKit background
  /// handler is registered HERE as well: when the app is killed this is the
  /// only engine alive, and without it a Decline tapped on the notification
  /// reaches nobody (E40, CE).
  static Future<void> ensureReady() async {
    markBackgroundIsolate();
    if (_ready) return;
    _ready = true;
    CallPlatform.instance = const VibeCallPlatform();
    // The call logic (ringing ack, decline) needs ApiClient + the session.
    await _restoreSession();
    await CallKitService.registerBackgroundHandler(onCallKitBackgroundEvent);
  }
}

/// No call timer that ends a call locally may run here: the accept never
/// reaches this isolate (A1). A handler that runs in the UI isolate (it
/// hosts the isolate bridge) is left alone.
void markBackgroundIsolate() {
  if (!CallIsolateBridge.isHost) CallRuntime.isUiIsolate = false;
}

Future<void> _restoreSession() async {
  try {
    await SessionStore.instance.restore();
  } catch (e) {
    Log.w('CallBackground', 'session restore: $e');
  }
}

/// Android: a plugin event while no UI isolate listens (`@pragma` entry).
/// It cannot touch any UI and assumes no call state: it does the smallest
/// durable thing.
@pragma('vm:entry-point')
Future<void> onCallKitBackgroundEvent(CallEvent event) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    markBackgroundIsolate();
    await AppPrefs.init();
    try {
      // Another isolate may have written since this one cached.
      await AppPrefs.instance.reloadCache();
    } catch (_) {}
    CallPlatform.instance = const VibeCallPlatform();
    await _restoreSession();
    final s = CallKitService.translate(event);
    if (s == null || s.isCompliance || s.callId.isEmpty) return;
    Log.d('CallBackground', '${s.action.name} ${s.callId}');
    switch (s.action) {
      case CallKitAction.accepted:
        // The plugin is launching the UI isolate; the call logic's
        // reconcile takes the accept from here (`/UpdateCall` not sent).
        await CallSignals.savePendingAccept(s.extra, apiDone: false);
        Log.w('CallAccept', 'background isolate: accept ${s.callId} saved');
      case CallKitAction.declined:
        await HeadlessCallEnd.decline(s.callId, s.extra);
        await CallSignals.onNativeDeclined(
          s.callId,
          apiDone: true,
          payload: s.extra,
        );
      case CallKitAction.ended:
      case CallKitAction.callback:
        // The ongoing notification's Hang up, no UI isolate.
        await HeadlessCallEnd.hangUp(s.callId, s.extra);
      case CallKitAction.timedOut:
        // Local only: the caller and the backend own "missed".
        await NativeCallMarks.markEnded(s.callId);
      default:
        break;
    }
  } catch (e, st) {
    Log.e('CallBackground', e, st);
  }
}
