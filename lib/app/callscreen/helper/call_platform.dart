import 'call_session.dart';

/// What the call logic needs from the native call UI (CallKit on iOS,
/// `flutter_callkit_incoming` notifications / Telecom on Android). The push
/// and native layer installs the real one at boot
/// (`CallPlatform.instance = …`); until then, and in tests, nothing happens.
///
/// Every method must never throw: call teardown must always complete.
abstract class CallPlatform {
  const CallPlatform();

  static CallPlatform instance = const _NoopCallPlatform();

  /// Remove the system call UI for [callId] without echoing a decline/end
  /// back (iOS `reportCall(endedAt:)`: clears the Dynamic Island, mem #10/#12;
  /// Android: end the plugin call + ongoing notification). Call on every
  /// local end and when the session reaches ended.
  Future<void> endNativeCall(String callId);

  /// The call connected: Android ongoing-call notification (FGS keeps the
  /// mic alive in the background), iOS marks the CallKit call connected.
  Future<void> markConnected(CallSession call);

  /// In-app Accept while a system ringer for [callId] is up (iOS CallKit
  /// background ring then app opened; Android notification): answer it
  /// natively so the system UI and audio session follow.
  Future<void> answerNativeRinging(String callId);

  /// Device locked right now (RN `isDeviceLocked`).
  Future<bool> isDeviceLocked();

  /// Android: show the call screens over the keyguard while a call is live.
  Future<void> setShowOverLockScreen(bool on);

  /// Android Telecom audio route (speaker / earpiece); iOS: no-op (Agora
  /// owns the route).
  Future<void> setSpeaker(bool on);

  /// Android: leave the app (RN `minimizeApp`) after a call that started on
  /// the lock screen. iOS: no-op.
  Future<void> minimizeApp();

  /// Caller: the outgoing call started (app still in front). Android starts
  /// the ongoing-call foreground service now: Android 12+ refuses to start
  /// it (and 14 the mic type) once the app is in the background. iOS: no-op.
  Future<void> markOutgoing(CallSession call) async {}

  /// A system ringer (iOS CallKit / Android plugin) is up for [callId], so
  /// the in-app screen must not ring on top of it and an in-app Accept must
  /// answer it natively.
  Future<bool> isNativeRinging(String callId) async => false;
}

class _NoopCallPlatform extends CallPlatform {
  const _NoopCallPlatform();

  @override
  Future<void> endNativeCall(String callId) async {}

  @override
  Future<void> markConnected(CallSession call) async {}

  @override
  Future<void> answerNativeRinging(String callId) async {}

  @override
  Future<bool> isDeviceLocked() async => false;

  @override
  Future<void> setShowOverLockScreen(bool on) async {}

  @override
  Future<void> setSpeaker(bool on) async {}

  @override
  Future<void> minimizeApp() async {}
}
