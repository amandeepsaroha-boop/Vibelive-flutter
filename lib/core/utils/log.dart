import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Debug-only logging. Errors are always forwarded to [developer.log] so a
/// crash reporter can be attached later in one place.
///
/// A release / profile build made with `--dart-define=CALL_TRACE=true` also
/// prints [d] and [w] to logcat / the console (device diagnosis of the call
/// flow: `adb logcat | grep -E 'CallAccept|CallFlow|CallEngine'`).
abstract final class Log {
  static const _trace = bool.fromEnvironment('CALL_TRACE');

  static void d(String tag, Object? message) {
    if (kDebugMode) {
      developer.log('$message', name: tag);
    } else if (_trace) {
      debugPrint('[$tag] $message');
    }
  }

  static void w(String tag, Object? message) {
    if (!kDebugMode && !_trace) return;
    developer.log('⚠️ $message', name: tag, level: 900);
    debugPrint('[$tag] ⚠️ $message'); // visible in `flutter run` / logcat
  }

  static void e(String tag, Object? error, [StackTrace? stackTrace]) {
    developer.log(
      '❌ $error',
      name: tag,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    if (kDebugMode) debugPrint('[$tag] ❌ $error');
  }
}
