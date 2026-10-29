import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/events/auth_events.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../api/authscreen/auth_queries.dart';
import 'auth_navigation.dart';

/// Shared moves of the post-login steps (age gate, language).
abstract final class OnboardingActions {
  /// Next step, or Home (RN `navigateAfterAuth`): a stack reset.
  /// [from]: the step being left (`age_gate`, `language`), for analytics.
  static Future<void> continueIntoApp(
    BuildContext context, {
    String? from,
  }) async {
    final route = await nextAuthRoute();
    if (route == AppRoutes.home) {
      final s = SessionStore.instance.value;
      AuthEvents.onboardingCompleted(
        userKey: s.userDocumentId ?? s.userId?.toString(),
        steps: from,
      );
    }
    if (context.mounted) context.go(route);
  }

  /// "Not you? Sign out": server logout, then the router guard shows login.
  static Future<void> signOut() => logout();
}
