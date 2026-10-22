import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/log.dart';
import '../../authscreen/helper/auth_navigation.dart';
import 'call_controller.dart';
import 'call_session.dart';
import 'state/call_constants.dart';

/// What `/call/incoming` should do now (RN IncomingCallScreen exit rules).
enum IncomingRouteAction { stay, toCall, exit }

/// Route rules the call screens apply (pure, testable).
abstract final class CallRouteRules {
  /// `/call` mounted with no call to show → leave for Home (E-60, RN
  /// empty-store bounce). Every auto-accept path fills the store first.
  static bool callScreenIsEmpty(CallSession s) =>
      s.callId == null &&
      (s.phase == CallPhase.idle || s.phase == CallPhase.ended);

  /// [bootstrapped]: the screen has been up [CallTimings.incomingBootstrapped];
  /// [sawRinging]: it saw this call ringing at least once.
  static IncomingRouteAction incoming(
    CallSession s, {
    required bool bootstrapped,
    required bool sawRinging,
  }) {
    // Answered (here, CallKit, a notification): straight to the call.
    if (s.phase == CallPhase.accepted || s.phase == CallPhase.ongoing) {
      return IncomingRouteAction.toCall; // E-65
    }
    final over = s.phase == CallPhase.idle || s.phase == CallPhase.ended;
    if (!over) return IncomingRouteAction.stay;
    // Mounted before the store was filled (hydration gap): give it the
    // bootstrap window before leaving.
    return bootstrapped || sawRinging
        ? IncomingRouteAction.exit
        : IncomingRouteAction.stay;
  }
}

/// Call navigation through the global [appRouter] (RN `safePush` /
/// `safeReplace`): one pending slot while the router is not on screen yet
/// (cold start, background launch), replayed when it is (E-59).
abstract final class CallNavigator {
  static String? _pending;
  static DateTime? _pendingSince;
  static Timer? _retry;

  /// A navigator is mounted.
  static bool get isReady => rootNavigatorKey.currentState != null;

  /// Current path, null when the router is not ready.
  static String? get location {
    if (!isReady) return null;
    try {
      return appRouter.state.uri.path;
    } catch (_) {
      return null;
    }
  }

  static bool get onCallRoute => location?.startsWith(AppRoutes.call) ?? false;

  /// Incoming screen for the ringing call. False when the router is not
  /// ready (the foreground presenter retries, then parks it).
  static bool showIncoming() {
    if (!isReady) return false;
    if (location == AppRoutes.incomingCall) return true;
    return _go(AppRoutes.incomingCall);
  }

  /// [showIncoming], parked until the router is ready.
  static void toIncoming() {
    if (!showIncoming()) queue(AppRoutes.incomingCall);
  }

  /// The call screen (outgoing, accepted, auto-accepted, return to call).
  /// An auto-accept never passes through `/call/incoming` (mem #7, E-34).
  static void toCall() {
    if (!isReady) return queue(AppRoutes.call);
    _clearPending();
    _go(AppRoutes.call);
  }

  /// `?tab=` of Home that the caller lands on after a call (decision 5).
  static const discoverTab = 'discover';

  /// Seam: where a signed-in user belongs (login, age gate, language,
  /// Home). Tests replace it.
  @visibleForTesting
  static Future<String> Function() authRoute = nextAuthRoute;

  /// A call screen replaced the splash / login / onboarding stack (cold
  /// start): leaving it must re-run the post-auth routing (U12).
  static bool _overAuth = false;

  /// Home ([tab]: its `?tab=`), replacing the call routes. Not queued: a
  /// cold start reaches Home through the splash anyway. After a call that
  /// started over the splash, the post-auth route wins (e.g. the language
  /// step) once the call is over.
  static void toHome({String? tab}) {
    _clearPending();
    if (!isReady) return;
    final home = tab == null ? AppRoutes.home : '${AppRoutes.home}?tab=$tab';
    if (!_overAuth || CallController.instance.value.phase.isActive) {
      _go(home);
      return;
    }
    _overAuth = false;
    unawaited(_toAuthRoute(home));
  }

  static Future<void> _toAuthRoute(String home) async {
    String route;
    try {
      route = await authRoute().timeout(CallTimings.authRouteWait);
    } catch (_) {
      route = AppRoutes.home;
    }
    // A new call took over meanwhile: its screens own the navigation.
    if (CallController.instance.value.phase.isActive) return;
    _go(route == AppRoutes.home ? home : route);
  }

  /// Parks [path] until the router is ready (one slot, last wins).
  static void queue(String path) {
    _pending = path;
    _pendingSince ??= DateTime.now();
    _retry ??= Timer.periodic(CallTimings.navigationRetry, (_) => flush());
  }

  /// Replays the parked navigation if it still applies.
  static void flush() {
    final path = _pending;
    if (path == null) return _clearPending();
    if (!isReady) {
      final since = _pendingSince;
      if (since != null &&
          DateTime.now().difference(since) > CallTimings.navigationGiveUp) {
        _clearPending();
      }
      return;
    }
    _clearPending();
    final phase = CallController.instance.value.phase;
    if (path == AppRoutes.call && !phase.isActive) return;
    if (path == AppRoutes.incomingCall && phase != CallPhase.ringing) return;
    if (path == AppRoutes.incomingCall) {
      showIncoming();
    } else {
      _go(path);
    }
  }

  static bool _go(String path) {
    final at = location;
    if (at == path) return true;
    try {
      if (!path.startsWith(AppRoutes.call)) {
        // Home, or the post-auth route: replaces the call routes.
        appRouter.go(path);
      } else if (at == null ||
          at == AppRoutes.splash ||
          at == AppRoutes.login ||
          at.startsWith('/onboarding')) {
        // Nothing worth keeping under the call: replace the stack.
        _overAuth = true;
        appRouter.go(path);
      } else if ((path == AppRoutes.call && at == AppRoutes.incomingCall) ||
          (path == AppRoutes.incomingCall && at == AppRoutes.call)) {
        // Accept replaces the ring; a new ring replaces a finished call's
        // summary (a live call never gets here: a second ring is refused).
        unawaited(appRouter.pushReplacement<void>(path));
      } else {
        unawaited(appRouter.push<void>(path));
      }
      return true;
    } catch (e) {
      Log.w('CallNavigator', 'navigate $path: $e');
      return false;
    }
  }

  static void _clearPending() {
    _pending = null;
    _pendingSince = null;
    _retry?.cancel();
    _retry = null;
  }

  @visibleForTesting
  static String? get debugPending => _pending;

  @visibleForTesting
  static void debugReset() {
    _clearPending();
    _overAuth = false;
    authRoute = nextAuthRoute;
  }

  @visibleForTesting
  static bool get debugOverAuth => _overAuth;

  @visibleForTesting
  static set debugOverAuth(bool on) => _overAuth = on;
}
