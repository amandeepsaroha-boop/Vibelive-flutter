import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../api/authscreen/auth_queries.dart';
import 'auth_navigation.dart';

/// Shared moves of the post-login steps (age gate, language).
abstract final class OnboardingActions {
  /// Next step, or Home (RN `navigateAfterAuth`): a stack reset.
  static Future<void> continueIntoApp(BuildContext context) async {
    final route = await nextAuthRoute();
    if (context.mounted) context.go(route);
  }

  /// "Not you? Sign out": server logout, then the router guard shows login.
  static Future<void> signOut() => logout();
}
