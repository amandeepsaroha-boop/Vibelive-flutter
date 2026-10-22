import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../network/api_exception.dart';
import '../utils/log.dart';

/// Catches everything that escapes a widget or a Future so the app never
/// dies silently. Hook a crash reporter into [report] later.
abstract final class AppErrorHandler {
  static void init() {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      report(details.exception, details.stack);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };

    if (kReleaseMode) {
      // A broken widget shows an empty box in release, not a red screen.
      ErrorWidget.builder = (_) => const SizedBox.shrink();
    }
  }

  static void report(Object error, StackTrace? stack) {
    // Expected API failures are handled by the UI; don't log them as crashes.
    if (error is ApiException && error.type == ApiErrorType.cancelled) return;
    Log.e('Uncaught', error, stack);
  }
}
