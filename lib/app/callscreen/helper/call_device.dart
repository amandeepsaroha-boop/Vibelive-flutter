import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// Platform facts the call logic branches on, overridable in tests.
abstract final class CallDevice {
  @visibleForTesting
  static bool? debugIsIOS;

  @visibleForTesting
  static bool? debugForeground;

  static bool get isIOS => debugIsIOS ?? Platform.isIOS;

  /// The app is on screen (`resumed`). A VoIP / CallKit launch runs Dart in
  /// the background: no camera, no prompts, no navigation yet.
  static bool get isForeground {
    final forced = debugForeground;
    if (forced != null) return forced;
    try {
      return WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
    } catch (_) {
      return false;
    }
  }
}
