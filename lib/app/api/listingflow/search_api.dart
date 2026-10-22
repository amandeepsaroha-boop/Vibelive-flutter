import '../../../core/network/api_client.dart';
import 'listing_api.dart';
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

  /// The hits' full cards in ONE batched read (never one request per row),
  /// keyed by expert-profile documentId: their verification badges, and a
  /// profile that opens at once when a hit is tapped.
  static Future<Map<String, HostCard>> fetchHosts(
    List<String> expertDocumentIds,
  ) async {
    final hosts = await ListingApi.fetchCards(expertDocumentIds);
    return {for (final host in hosts) ?host.expertProfileDocumentId: host};
  }
}
