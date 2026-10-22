import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'auth_errors.dart';
import 'interests_models.dart';

/// Admin-managed interests form and the user's answers. Used by the
/// onboarding language step, the expertise screen and support topics.
abstract final class InterestsApi {
  static Map<String, dynamic> get _appQuery => {
    'app': Env.appPlatform,
    'appKey': Env.appPlatform,
  };

  static Future<InterestForm> fetchForm() => _guard(
    () async => InterestForm.fromResponse(
      await ApiClient.get('/interests/form', query: _appQuery),
    ),
  );

  static Future<MyInterests> fetchMyInterests() => _guard(
    () async => MyInterests.fromResponse(
      await ApiClient.get('/me/interests', query: _appQuery),
    ),
  );

  /// Replaces the whole answer set: send every answer, not just the changed
  /// ones. [source]: `onboarding`, `profile`…
  static Future<SaveInterestsResult> saveMyInterests(
    InterestSelections selections, {
    String source = 'onboarding',
  }) => _guard(() async {
    final body = await ApiClient.put(
      '/me/interests',
      // Saving re-derives matching data server-side (RN: 30 s).
      timeout: const Duration(seconds: 30),
      data: {
        'selections': normalizeInterestSelections(selections),
        'source': source.isEmpty ? 'onboarding' : source,
      },
      query: _appQuery,
    );
    return SaveInterestsResult.fromResponse(body);
  });

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      throw AuthErrors.interests(e);
    }
  }
}
