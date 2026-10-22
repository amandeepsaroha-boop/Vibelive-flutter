import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Debug-only logging. Errors are always forwarded to [developer.log] so a
/// crash reporter can be attached later in one place.
abstract final class Log {
  static void d(String tag, Object? message) {
    if (kDebugMode) developer.log('$message', name: tag);
  }

  static void w(String tag, Object? message) {
    if (!kDebugMode) return;
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
