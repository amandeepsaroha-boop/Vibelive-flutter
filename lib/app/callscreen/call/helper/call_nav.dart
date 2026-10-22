import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';

/// Location of the page on top ('' without a [GoRouter]). Not
/// `configuration.uri`: that stays on the page below after a `push`.
String callTopLocation(GoRouter? router) {
  final config = router?.routerDelegate.currentConfiguration;
  if (config == null || config.isEmpty) return '';
  return config.last.matchedLocation;
}

/// One of the call pages (`/call`, `/call/incoming`) is on top.
bool onCallRoutes(GoRouter? router) =>
    callTopLocation(router).startsWith(AppRoutes.call);

/// `/call` is the page on top: a deep link pushed over the call screen is
/// not (U4). False once [context] is gone; true without a [GoRouter]
/// (nothing can be on top of the screen then).
bool callScreenOnTop(BuildContext context) {
  if (!context.mounted) return false;
  final router = GoRouter.maybeOf(context);
  return router == null || callTopLocation(router) == AppRoutes.call;
}

/// Incoming → call screen (answered here or elsewhere). Same move as the
/// logic's `CallNavigator.toCall` (replace the incoming page, keep what is
/// under it), so whichever runs second finds `/call` on top and does
/// nothing.
void goToCallScreen(BuildContext context) {
  if (!context.mounted) return;
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  final top = callTopLocation(router);
  if (top == AppRoutes.call) return;
  if (top == AppRoutes.incomingCall) {
    unawaited(router.pushReplacement<void>(AppRoutes.call));
  } else {
    router.go(AppRoutes.call);
  }
}
