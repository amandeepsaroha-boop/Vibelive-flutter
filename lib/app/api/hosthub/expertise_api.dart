import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import 'expertise_models.dart';

/// The host's service areas (`/me/service-areas`): answers to the same
/// question catalog as the interests form.
abstract final class ExpertiseApi {
  static Map<String, dynamic> get _app => {
    'app': Env.appPlatform,
    'appKey': Env.appPlatform,
  };

  static Future<ExpertiseSelections> fetchMine() async =>
      ExpertiseSelections.fromResponse(
        await ApiClient.get('/me/service-areas', query: _app),
      );

  /// [source]: `settings`, or `professional-details` during onboarding.
  static Future<ExpertiseSaveResult> save(
    ExpertiseAnswers selections, {
    String source = 'settings',
  }) async => ExpertiseSaveResult.fromResponse(
    await ApiClient.put(
      '/me/service-areas',
      query: _app,
      // Saving re-derives the host's service areas server-side (RN: 30 s).
      timeout: const Duration(seconds: 30),
      data: {
        'selections': ExpertiseSelections.normalize(selections),
        'source': source.isEmpty ? 'settings' : source,
      },
    ),
  );
}
