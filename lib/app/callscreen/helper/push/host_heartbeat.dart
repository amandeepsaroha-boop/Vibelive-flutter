import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/authscreen/push_api.dart';

/// Foreground presence for hosts (RN `useHostHeartbeat`): without a direct
/// signal the presence cron probes, and after a few unanswered probes marks
/// a host OFFLINE while they sit in the app.
///
/// Beats once on becoming active, then every [interval], only while the app
/// is in front and a host is signed in. Never in the background: claiming
/// presence for a frozen app is the lie this stops telling. One request at a
/// time; failures cost one interval and are only logged.
abstract final class HostHeartbeat {
  static const interval = Duration(minutes: 1);

  static Timer? _timer;
  static bool _inFlight = false;
  static bool _attached = false;

  /// Follows the session (sign-in, sign-out, becoming a host). Lifecycle
  /// changes come through [sync] / [stop] from `CallFlow`.
  static void attach() {
    if (_attached) return;
    _attached = true;
    SessionStore.instance.addListener(sync);
  }

  static bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Starts or stops the beat for the current session and lifecycle.
  static void sync() {
    final s = SessionStore.instance.value;
    if (s.isAuthenticated && s.isExpert && _foreground) {
      _start();
    } else {
      stop();
    }
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static void _start() {
    if (_timer != null) return;
    unawaited(_beat());
    _timer = Timer.periodic(interval, (_) => unawaited(_beat()));
  }

  static Future<void> _beat() async {
    if (_inFlight || !_foreground) return;
    _inFlight = true;
    try {
      await PushApi.expertHeartbeat(via: 'foreground');
    } catch (e) {
      Log.w('HostHeartbeat', 'failed: $e');
    } finally {
      _inFlight = false;
    }
  }
}
