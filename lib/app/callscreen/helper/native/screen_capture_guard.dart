import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/utils/log.dart';
import '../call_controller.dart';

/// Keeps a video call out of screenshots and screen recordings, for the
/// length of the call (calling → ended, the minimised call and PiP too).
///
/// - Android: `FLAG_SECURE` on the window. The system refuses screenshots
///   and records the window as black; it allows no custom image there.
/// - iOS cannot block either. While the screen is being recorded, mirrored
///   or AirPlayed, [shielded] is true and `CaptureShield` covers the app
///   with the logo, so that is what the recording gets. Screenshots on iOS
///   cannot be prevented by an app.
abstract final class ScreenCaptureGuard {
  static const _android = MethodChannel('com.angrymamba.vibelive/call_ui');
  static const _ios = MethodChannel('com.angrymamba.vibelive/callkit');
  static const _tag = 'ScreenGuard';
  static const _pollEvery = Duration(seconds: 1);

  static final _shielded = ValueNotifier<bool>(false);
  static bool _attached = false;
  static bool _secure = false;
  static Timer? _poll;

  /// iOS: the screen is being captured during a video call.
  static ValueListenable<bool> get shielded => _shielded;

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  static bool get _wanted {
    final s = CallController.instance.value;
    return s.phase.isActive && s.isVideo;
  }

  /// Once, from the app root.
  static void attach() {
    if (_attached || !_supported) return;
    _attached = true;
    CallController.instance.session.addListener(_apply);
    // A recreated activity starts without the flag: re-apply on return.
    AppLifecycleListener(onResume: () => _apply(force: true));
    _apply();
  }

  static void _apply({bool force = false}) {
    final want = _wanted;
    if (want == _secure && !force) return;
    _secure = want;
    if (Platform.isAndroid) {
      unawaited(_setAndroidSecure(want));
    } else if (want) {
      _poll ??= Timer.periodic(_pollEvery, (_) => unawaited(_checkCaptured()));
      unawaited(_checkCaptured());
    } else {
      _poll?.cancel();
      _poll = null;
      _shielded.value = false;
    }
  }

  static Future<void> _setAndroidSecure(bool secure) async {
    try {
      await _android.invokeMethod<void>('setSecureScreen', {'secure': secure});
    } catch (e) {
      Log.w(_tag, 'setSecureScreen($secure): $e');
    }
  }

  static Future<void> _checkCaptured() async {
    try {
      final captured = await _ios.invokeMethod<bool>('isScreenCaptured');
      _shielded.value = _secure && captured == true;
    } catch (e) {
      Log.w(_tag, 'isScreenCaptured: $e');
    }
  }
}
