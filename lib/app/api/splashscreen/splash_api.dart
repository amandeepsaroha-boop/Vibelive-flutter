import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import 'splash_models.dart';

/// Raw endpoint calls. No caching here: use the hooks in `splash_queries.dart`
/// (or `queryCache.fetchQuery` outside widgets).
abstract final class SplashApi {
  /// One request covers every consumer (update notice, Agora app id, ping
  /// config), so all of them share a single cache entry.
  static Future<AppConfig> fetchAppConfig() async {
    final body = await ApiClient.get(
      '/app-config',
      query: {
        'populate[0]': 'latest_android_version',
        'populate[1]': 'latest_ios_version',
      },
    );
    return AppConfig.fromResponse(body);
  }

  /// Onboarding marquee topics. Fewer than 4 rows means "use the fallback".
  static Future<List<String>> fetchHostTopics() async {
    final body = await ApiClient.get(
      '/host-topics',
      retry: false,
      timeout: const Duration(seconds: 4),
    );
    final rows = body is Map ? body['data'] : null;
    if (rows is! List) return const [];
    final labels = [for (final row in rows) ?J.str(Strapi.map(row)?['label'])];
    return labels.length < 4 ? const [] : labels;
  }
}
