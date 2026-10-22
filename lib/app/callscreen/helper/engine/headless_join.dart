import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/utils/log.dart';
import '../call_device.dart';
import '../state/call_constants.dart';
import 'call_engine.dart';

/// The background join after a system-UI answer (RN `joinAgoraHeadless`,
/// mem #14): audio only, so an accepted call has sound with the app never
/// opened. On iOS it is parked until CallKit activates the audio session
/// (joining before gives a connected call with no audio), with a
/// [CallTimings.audioSessionFallback] fallback (CE).
class HeadlessJoin {
  HeadlessJoin._();
  static final instance = HeadlessJoin._();

  bool _audioActive = false;
  Future<void> Function()? _parked;
  Timer? _fallback;

  /// Joins now, or once the audio session is up (iOS).
  Future<void> joinWhenAudioReady({
    required String channel,
    required String token,
    required int uid,
    required bool video,
  }) async {
    Future<void> run() async {
      _fallback?.cancel();
      _fallback = null;
      _parked = null;
      final joined = await CallEngine.instance.join(
        channel: channel,
        token: token,
        uid: uid,
        video: video,
        headless: true,
      );
      // Already in front (in-app accept of a CallKit ring): camera now.
      if (joined && CallDevice.isForeground) {
        await CallEngine.instance.ensureVideoIfNeeded();
      }
    }

    if (!CallDevice.isIOS || _audioActive) return run();
    _parked = run;
    _fallback?.cancel();
    _fallback = Timer(CallTimings.audioSessionFallback, () {
      final parked = _parked;
      if (parked == null) return;
      Log.w('HeadlessJoin', 'audio session never activated: joining anyway');
      unawaited(parked());
    });
  }

  /// CallKit `didActivate`: run the parked join now.
  void onAudioSessionActivated() {
    _audioActive = true;
    final parked = _parked;
    if (parked != null) unawaited(parked());
  }

  /// The call is over: drop a parked join and leave (RN
  /// `leaveAgoraHeadless`). The next call's session activates again.
  Future<void> leave() async {
    cancel();
    await CallEngine.instance.leave();
  }

  /// Forget a parked join and the session state, without leaving.
  void cancel() {
    _fallback?.cancel();
    _fallback = null;
    _parked = null;
    _audioActive = false;
  }

  bool get isParked => _parked != null;

  @visibleForTesting
  void debugReset() => cancel();
}
