import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/log.dart';
import '../call_signals.dart';
import '../push/call_push_handler.dart';
import 'callkit_service.dart';
import 'native_call_bridge.dart';
import 'native_call_marks.dart';
import '../call_platform.dart';

/// Android: a tap on the incoming-call notification (or its full-screen
/// intent) opens OUR incoming screen (CE `IncomingCallIntents`; RN pointed
/// its notification at `MainActivity`). `IncomingCallRedirect` hands the
/// call id to `MainActivity`, which parks it for a cold start
/// (`takeLaunchCall`) or sends it to a running app (`showIncomingCall`).
abstract final class IncomingCallIntents {
  static const _tag = 'IncomingCallIntents';
  static bool _listening = false;
  static String? _openingId;

  /// Whether this process was started (or brought forward) by an incoming
  /// call (the splash can skip its logo).
  static bool launchedOnIncomingCall = false;

  /// Notified when the system PiP mode changes (RN `PiPModeChanged`).
  static void Function(bool inPip)? onPipChanged;

  static Future<void> init() async {
    if (!Platform.isAndroid || _listening) return;
    _listening = true;
    NativeCallBridge.setAndroidHandler(_onNativeCall);
    final launch = await NativeCallBridge.takeLaunchCall();
    if (launch != null) {
      launchedOnIncomingCall = true;
      await open(launch);
    }
  }

  static Future<dynamic> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'showIncomingCall':
        launchedOnIncomingCall = true;
        await open('${call.arguments ?? ''}');
      case 'pipChanged':
        onPipChanged?.call(call.arguments == true);
    }
    return null;
  }

  /// Presents the ringing call [callId] in-app: its payload from the
  /// plugin's active calls (else the invite the ringer was shown for), the
  /// plugin's own sound and heads-up off (the in-app screen rings instead,
  /// A8), then the logic presents it (it drops a stale or ended one). The
  /// ringing ack the background isolate already sent is not sent again.
  static Future<void> open(String callId) async {
    if (callId.isNotEmpty && _openingId == callId) return;
    _openingId = callId;
    try {
      final payload = await _payloadFor(callId);
      if (payload == null) {
        Log.w(_tag, 'no payload for tapped call $callId');
        await NativeCallBridge.hideCallCover();
        return;
      }
      final id = '${payload['callId'] ?? callId}';
      // Locked (full-screen intent): keep the plugin's ringtone. Android
      // won't reliably play the app's own ringtone over the keyguard, so
      // hiding it cut the ring after ~2 s (RN kept the native ring too).
      if (!await CallPlatform.instance.isDeviceLocked()) {
        await CallKitService.hideIncoming(id);
      }
      await CallPushHandler.adoptBackgroundAck(id);
      await CallSignals.onInvite(
        payload,
        foreground: true,
        source: CallPushSource.notificationTap,
      );
      _dropCoverAfterFrame();
    } catch (e, st) {
      Log.e(_tag, e, st);
      await NativeCallBridge.hideCallCover();
    } finally {
      _openingId = null;
    }
  }

  static Future<Map<String, dynamic>?> _payloadFor(String callId) async {
    final calls = await CallKitService.activeCalls();
    for (final c in calls) {
      if (c.isAccepted) continue;
      if (callId.isEmpty || c.callId == callId) return c.extra;
    }
    if (callId.isEmpty) return null;
    return NativeCallMarks.invite(callId);
  }

  /// `CallPlatform` has no "call UI drew" signal: drop the native cover a
  /// moment after the frame that followed the presentation (the native side
  /// drops it after 4 s regardless).
  static void _dropCoverAfterFrame() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(milliseconds: 300), () {
        unawaited(NativeCallBridge.hideCallCover());
      });
    });
    SchedulerBinding.instance.scheduleFrame();
  }
}
