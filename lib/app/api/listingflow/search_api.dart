import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import 'listing_models.dart';
import 'search_models.dart';

/// Expert search: the same `GET /search` the Consultease app uses. All
/// ranking, matching and relevance happen server-side.
abstract final class SearchApi {
  static const defaultLimit = 15;

  static Future<SearchResults> search(
    String query, {
    int limit = defaultLimit,
  }) async {
    final body = await ApiClient.get(
      '/search',
      query: {'q': query.trim(), 'limit': limit},
    );
    return SearchResults.fromResponse(body);
  }

  /// Verification flags of [expertDocumentIds] in ONE batched read (never
  /// one request per row), keyed by expert-profile documentId.
  static Future<Map<String, HostBadges>> fetchBadges(
    List<String> expertDocumentIds,
  ) async {
    if (expertDocumentIds.isEmpty) return const {};
    final body = await ApiClient.get(
      '/expert-profiles',
      query: {
        for (var i = 0; i < expertDocumentIds.length; i++)
          'filters[documentId][\$in][$i]': expertDocumentIds[i],
        'populate[expert_verifications]': 'true',
        'fields[0]': 'documentId',
        'pagination[pageSize]': expertDocumentIds.length,
      },
    );
    return {
      for (final row in Strapi.list(body))
        J.str(row['documentId']) ?? '': HostBadges.fromRow(row),
    }..remove('');
  }
}
