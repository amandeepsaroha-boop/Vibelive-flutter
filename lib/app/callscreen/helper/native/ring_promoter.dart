import 'dart:io' show Platform;

import '../../../../core/utils/log.dart';
import '../call_controller.dart';
import '../call_platform.dart';
import '../call_ringtone.dart';
import '../call_runtime.dart';
import '../call_session.dart';
import '../flows/incoming_flow.dart';
import 'native_call_bridge.dart';

/// iOS (I4): an in-app ring (FOREGROUND-SUPPRESS: no CallKit) when the app
/// leaves the screen (Lock, Home, app switcher) would ring on with no
/// lock-screen UI and stop once iOS suspends the app. It is handed to
/// CallKit instead: the in-app ringtone stops, CallKit rings, and an in-app
/// Accept later answers the CallKit call (`answerNativeRinging`). Never
/// throws.
abstract final class RingPromoter {
  static const _tag = 'RingPromoter';
  static String? _promoted;

  /// `AppLifecycleState.hidden` / `paused` (UI isolate).
  static Future<void> onBackgrounded() async {
    if (!Platform.isIOS) return;
    try {
      final callId = _ringingHere();
      if (callId == null || _promoted == callId) return;
      if (IncomingFlow.isMarkedNativeRinging(callId)) return;
      if (await CallPlatform.instance.isNativeRinging(callId)) return;
      final payload = CallRuntime.ringingPayload;
      if (payload == null) return;
      _promoted = callId;
      // Never touches the audio session (mem #2): CallKit owns it next.
      await CallRingtone.silence();
      if (_ringingHere() != callId) return; // answered / ended meanwhile
      if (!await NativeCallBridge.promoteToCallKit(payload)) {
        Log.w(_tag, 'native refused to promote $callId');
        return;
      }
      IncomingFlow.markNativeRinging(callId);
      Log.d(_tag, 'promoted $callId to CallKit');
    } catch (e, st) {
      Log.e(_tag, e, st);
    }
  }

  /// The receiver call ringing in the app right now.
  static String? _ringingHere() {
    final s = CallController.instance.value;
    if (!s.isReceiver || s.phase != CallPhase.ringing) return null;
    final id = s.callId;
    return id == null || id.isEmpty ? null : id;
  }
}
