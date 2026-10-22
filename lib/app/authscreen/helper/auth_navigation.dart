import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../api/authscreen/auth_models.dart';
import '../../api/authscreen/onboarding_queries.dart';

/// Where the user belongs now (RN `decidePostAuthRoute`): login, the 18+
/// gate, the language step, or Home. Splash and login share it so the order
/// can never drift. Never throws: an unreachable server never blocks.
///
/// [confirmAgeGate]: cold start, where a stored verdict may be stale.
Future<String> nextAuthRoute({bool confirmAgeGate = false}) async {
  if (!SessionStore.instance.value.isAuthenticated) return AppRoutes.login;
  try {
    return switch (await nextOnboardingStep(confirmAgeGate: confirmAgeGate)) {
      OnboardingStep.signedOut => AppRoutes.login,
      OnboardingStep.ageGate => AppRoutes.onboardingAge,
      OnboardingStep.language => AppRoutes.onboardingLanguage,
      OnboardingStep.home => AppRoutes.home,
    };
  } catch (_) {
    return AppRoutes.home;
  }
}
