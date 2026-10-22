import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../../../core/utils/log.dart';

/// Dart side of the app's own native call channels. Every method never
/// throws (a missing channel in tests or a background engine is a no-op).
///
/// iOS: `com.angrymamba.vibelive/callkit` (+ `_events`), `VibeCallBridge.swift`.
/// Android: `com.angrymamba.vibelive/call_ui`, `MainActivity.kt`.
abstract final class NativeCallBridge {
  static const _ios = MethodChannel('com.angrymamba.vibelive/callkit');
  static const _iosEvents = EventChannel(
    'com.angrymamba.vibelive/callkit_events',
  );
  static const _android = MethodChannel('com.angrymamba.vibelive/call_ui');
  static const _tag = 'NativeCallBridge';

  // ── iOS ────────────────────────────────────────────────────────────────

  /// Native events: `voipPush {route, foreground, data}`, `nativeEnded
  /// {callId, status, durationSecs}`, `updateCallFailed {callId, payload}`,
  /// `unlocked`. Listen BEFORE [ready].
  static Stream<Map<String, dynamic>> events() {
    if (!Platform.isIOS) return const Stream.empty();
    return _iosEvents
        .receiveBroadcastStream()
        .where((e) => e is Map)
        .map((e) => _map(e as Map))
        .handleError((Object e) => Log.w(_tag, 'event stream: $e'));
  }

  /// Dart is listening: native stops queueing (and FOREGROUND-SUPPRESS may
  /// apply). Returns the events queued before.
  static Future<List<Map<String, dynamic>>> ready() async {
    final list = await _iosCall<List<Object?>>('ready');
    return [
      for (final e in list ?? const [])
        if (e is Map) _map(e),
    ];
  }

  /// What native HTTP needs while Dart may not run (§2.6).
  static Future<void> configure({
    required String apiBaseUrl,
    required String appPlatform,
    String? defaultToken,
    String? deviceId,
    String? userId,
  }) => _iosCall<void>('configure', {
    'apiBaseUrl': apiBaseUrl,
    'appPlatform': appPlatform,
    'defaultToken': ?defaultToken,
    'deviceId': ?deviceId,
    'userId': ?userId,
  });

  /// RN `syncNativeVoipAuthToken`: login, every refresh, logout (null).
  static Future<void> setAuthToken(String? token) =>
      _iosCall<void>('setAuthToken', {'token': token});

  /// Clears the CallKit call for [callId] with `reportCall(endedAt:)` (no
  /// `CXEndCallAction`, so no echo). 2 = remote ended, 4 = answered elsewhere.
  static Future<void> endCall(String callId, {int reason = 2}) =>
      _iosCall<void>('endCall', {'callId': callId, 'reason': reason});

  /// The call CallKit holds: `{uuid, callId, answered, payload}`, or null.
  static Future<Map<String, dynamic>?> liveCall() async {
    final m = await _iosCall<Map<Object?, Object?>>('liveCall');
    return m == null ? null : _map(m);
  }

  /// In-app Accept of the call CallKit is ringing: native requests the
  /// `CXAnswerCallAction` for its live UUID (the plugin's `setCallConnected`
  /// overwrote its stored call data with a bare id). The answer then runs
  /// the native accept path (`/UpdateCall`, ACTION_CALL_ACCEPT). False when
  /// nothing unanswered is live for [callId].
  static Future<bool> answerLive(String callId) async =>
      await _iosCall<bool>('answerLive', {'callId': callId}) ?? false;

  /// iOS `UIApplication.isProtectedDataAvailable` (false while locked, and
  /// before the first unlock since boot). Null when unknown (no channel:
  /// another platform, a background engine, tests).
  static Future<bool?> isProtectedDataAvailable() =>
      _iosCall<bool>('isProtectedDataAvailable');

  /// The accept snapshot native saved at CXAnswerCallAction (read once):
  /// `{at: ms, payload: {...}, updateFailed?: true}`.
  static Future<Map<String, dynamic>?> consumePendingAccept() async {
    final m = await _iosCall<Map<Object?, Object?>>('consumePendingAccept');
    return m == null ? null : _map(m);
  }

  /// Native `/call/Callend` bodies whose request failed.
  static Future<List<Map<String, dynamic>>> drainFailedEnds() async {
    final list = await _iosCall<List<Object?>>('drainFailedEnds');
    return [
      for (final e in list ?? const [])
        if (e is Map) _map(e),
    ];
  }

  /// In-app ring promoted to CallKit when the app goes to the background.
  /// Native refuses (false) when anything is live or [payload] is no ring.
  static Future<bool> promoteToCallKit(Map<String, dynamic> payload) async =>
      await _iosCall<bool>('promoteToCallKit', {'payload': payload}) ?? false;

  // ── both platforms ─────────────────────────────────────────────────────

  static Future<bool> isDeviceLocked() async =>
      (Platform.isIOS
          ? await _iosCall<bool>('isDeviceLocked')
          : await _androidCall<bool>('isDeviceLocked')) ??
      false;

  /// `speaker` / `earpiece` / `bluetooth`: iOS on Agora's session, Android
  /// through the Telecom connection of [callId].
  static Future<bool> setAudioRoute(String route, {String? callId}) async =>
      (Platform.isIOS
          ? await _iosCall<bool>('setRoute', {'route': route})
          : await _androidCall<bool>('setCallAudioRoute', {
              'callId': callId,
              'route': route,
            })) ??
      false;

  static Future<bool> bluetoothAvailable() async =>
      (Platform.isIOS
          ? await _iosCall<bool>('bluetoothAvailable')
          : await _androidCall<bool>('bluetoothAvailable')) ??
      false;

  // ── Android ────────────────────────────────────────────────────────────

  /// Handles `showIncomingCall` / `pipChanged` from `MainActivity`.
  static void setAndroidHandler(Future<dynamic> Function(MethodCall) handler) {
    if (!Platform.isAndroid) return;
    _android.setMethodCallHandler(handler);
  }

  /// The call a notification tap launched the app for (cold start), once.
  static Future<String?> takeLaunchCall() =>
      _androidCall<String>('takeLaunchCall');

  /// Show the app over the keyguard while a call is live (per call).
  static Future<void> setLockedActivity(bool on) =>
      _androidCall<void>('setLockedActivity', on);

  /// Declines tapped on the call notification while the process was dead
  /// (no engine heard them), kept natively by `VibeApplication`: the ring
  /// payloads (`callId`, `receiverId`, `type`, `calleridDocID`), read once.
  static Future<List<Map<String, dynamic>>> drainNativeDeclines() async {
    final list = await _androidCall<List<Object?>>('drainNativeDeclines');
    return [
      for (final e in list ?? const [])
        if (e is Map) _map(e),
    ];
  }

  /// Drop the cover hiding the previous screen until the call UI drew.
  static Future<void> hideCallCover() => _androidCall<void>('hideCallCover');

  /// Leave the app and take it out of Recents (call ended on a locked phone).
  static Future<void> exitApp() => _androidCall<void>('exitApp');

  /// RN `minimizeApp` (`moveTaskToBack`).
  static Future<void> minimizeApp() => _androidCall<void>('minimizeApp');

  /// Volume keys: `ring` / `call` / default.
  static Future<void> setVolumeControlStream(String mode) =>
      _androidCall<void>('setVolumeControlStream', mode);

  /// `{routes: [...], current: ...}` Telecom says the call can use.
  static Future<Map<String, dynamic>> callAudioRoutes(String callId) async {
    final m = await _androidCall<Map<Object?, Object?>>('callAudioRoutes', {
      'callId': callId,
    });
    return m == null ? const {} : _map(m);
  }

  /// RN proximity wake lock for audio calls.
  static Future<void> acquireProximityLock() =>
      _androidCall<void>('acquireProximityLock');
  static Future<void> releaseProximityLock() =>
      _androidCall<void>('releaseProximityLock');

  /// RN PiPModule (off unless [enabled]).
  static Future<void> pipSetCallActive({
    required bool enabled,
    required bool active,
    required bool video,
  }) => _androidCall<void>('pipSetCallActive', {
    'enabled': enabled,
    'active': active,
    'video': video,
  });
  static Future<bool> pipEnter() async =>
      await _androidCall<bool>('pipEnter') ?? false;

  // ──────────────────────────────────────────────────────────────────────

  static Future<T?> _iosCall<T>(String method, [Object? args]) =>
      Platform.isIOS ? _invoke<T>(_ios, method, args) : Future.value();

  static Future<T?> _androidCall<T>(String method, [Object? args]) =>
      Platform.isAndroid ? _invoke<T>(_android, method, args) : Future.value();

  static Future<T?> _invoke<T>(
    MethodChannel channel,
    String method,
    Object? args,
  ) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // background engine / tests: no activity channel
    } catch (e) {
      Log.w(_tag, '$method failed: $e');
      return null;
    }
  }

  static Map<String, dynamic> _map(Map<dynamic, dynamic> m) => {
    for (final e in m.entries)
      '${e.key}': e.value is Map ? _map(e.value as Map) : e.value,
  };
}
