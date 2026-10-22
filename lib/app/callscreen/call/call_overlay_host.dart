import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:vibration/vibration.dart';

import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../helper/call_signals.dart';
import 'callback_sheet.dart';
import 'helper/call_nav.dart';
import 'helper/callback_data.dart';

/// App-wide call UI that is not a screen (RN `CallManager` mounting
/// `CallbackModalListener`): shows the callback sheet whenever
/// [CallSignals.callbackRequest] carries a nudge. Mount it once around the
/// router's child:
///
/// ```dart
/// MaterialApp.router(builder: (context, child) =>
///     CallOverlayHost(child: child ?? const SizedBox.shrink()))
/// ```
///
/// Draws nothing itself; sheets go on the root navigator. A nudge that
/// arrives while a call page is on top waits until the user leaves it.
class CallOverlayHost extends StatefulWidget {
  const CallOverlayHost({
    super.key,
    required this.child,
    this.requests,
    this.onConsumed,
  });

  final Widget child;

  /// Nudges to show; defaults to [CallSignals.callbackRequest] (tests pass
  /// their own: the signal's notifier is private).
  final ValueListenable<CallbackRequest?>? requests;

  /// Called once a nudge was taken; defaults to
  /// [CallSignals.clearCallbackRequest].
  final VoidCallback? onConsumed;

  /// RN `Vibration.vibrate([0, 400, 300, 400])` on show.
  static const vibration = [0, 400, 300, 400];

  @override
  State<CallOverlayHost> createState() => _CallOverlayHostState();
}

class _CallOverlayHostState extends State<CallOverlayHost> {
  ValueNotifier<CallbackData>? _open;

  /// A nudge that came in on the call pages, shown once the user leaves
  /// them (U5). The newest wins.
  CallbackRequest? _held;
  GoRouter? _watched;

  ValueListenable<CallbackRequest?> get _requests =>
      widget.requests ?? CallSignals.callbackRequest;

  GoRouter? get _router {
    final ctx = rootNavigatorKey.currentContext;
    return ctx == null ? null : GoRouter.maybeOf(ctx);
  }

  @override
  void initState() {
    super.initState();
    _requests.addListener(_onRequest);
    // A nudge tapped before sign-in was restored shows once it is.
    SessionStore.instance.addListener(_onRequest);
    // A nudge that arrived before the app was up (notification tap).
    WidgetsBinding.instance.addPostFrameCallback((_) => _onRequest());
  }

  @override
  void didUpdateWidget(CallOverlayHost old) {
    super.didUpdateWidget(old);
    final before = old.requests ?? CallSignals.callbackRequest;
    if (before != _requests) {
      before.removeListener(_onRequest);
      _requests.addListener(_onRequest);
    }
  }

  @override
  void dispose() {
    _requests.removeListener(_onRequest);
    SessionStore.instance.removeListener(_onRequest);
    _unwatch();
    super.dispose();
  }

  Future<void> _onRequest() async {
    final request = _requests.value;
    if (request == null || !mounted) return;
    if (!SessionStore.instance.value.isAuthenticated) return;
    (widget.onConsumed ?? CallSignals.clearCallbackRequest)();
    if (_holdOnCallRoutes(request)) return;
    await _show(request);
  }

  /// The sheet never covers the incoming / call screen (and its Call
  /// button never starts a call over a live one): while a call page is on
  /// top, [request] waits for the user to leave. A cold-start tap waits
  /// the same way for splash / login to hand over to the app: a sheet
  /// pushed there is dropped when the router replaces those pages.
  bool _holdOnCallRoutes(CallbackRequest request) {
    final router = _router;
    if (router == null || !_mustWait(router)) return false;
    _held = request;
    if (!identical(_watched, router)) {
      _unwatch();
      _watched = router..routerDelegate.addListener(_onRoute);
    }
    return true;
  }

  void _onRoute() {
    final held = _held;
    if (held == null || !mounted || _mustWait(_watched)) return;
    _held = null;
    _unwatch();
    // Mid-navigation: a sheet pushed now would sit on the page that is
    // going away. Show it once the new page is in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !SessionStore.instance.value.isAuthenticated) return;
      unawaited(_show(held));
    });
  }

  static bool _mustWait(GoRouter? router) {
    final top = callTopLocation(router);
    return onCallRoutes(router) ||
        top == AppRoutes.splash ||
        top.startsWith(AppRoutes.login) ||
        top.startsWith('/onboarding');
  }

  void _unwatch() {
    _watched?.routerDelegate.removeListener(_onRoute);
    _watched = null;
  }

  Future<void> _show(CallbackRequest request) async {
    final data = await resolveCallback(request);
    if (data == null || !mounted) return;
    // A call page came up during the host lookup.
    if (_holdOnCallRoutes(request)) return;
    _buzz();
    final open = _open;
    if (open != null) {
      open.value = data; // newer nudge: same sheet, new host
      return;
    }
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final notifier = _open = ValueNotifier(data);
    try {
      await showCallbackSheet(ctx, notifier);
    } finally {
      // Not disposed: the closing sheet may still be listening.
      _open = null;
    }
  }

  void _buzz() {
    unawaited(() async {
      try {
        await Vibration.vibrate(pattern: CallOverlayHost.vibration);
      } catch (_) {
        // No vibrator / plugin (tests): the sheet still shows.
      }
    }());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
