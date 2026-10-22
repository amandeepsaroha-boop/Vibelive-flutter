import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import '../listingflow/listing_api.dart';
import '../listingflow/listing_models.dart';
import 'home_models.dart';

/// Discover tab feed. No caching here: use the hooks in `home_queries.dart`.
abstract final class HomeApi {
  static const pageSize = 16;

  /// Directory page: online hosts first, then by rank.
  static Future<HostPage> fetchFeedPage(int page) async {
    final body = await ApiClient.get(
      '/expert-profiles',
      query: {
        'pagination[page]': page,
        'pagination[pageSize]': pageSize,
        ...ListingApi.hostCardPopulate,
        'sort[0]': 'isActive:desc',
        'sort[1]': 'RankFactor:desc',
      },
    );
    return HostPage.fromResponse(body, page: page, pageSize: pageSize);
  }

  /// "Popular" tab, ranked server-side by demand (completed calls, then
  /// profile views). A client-side `rating >= 4` rule left the tab empty
  /// (almost no reviews) and only ever saw the pages already loaded.
  static Future<List<HostCard>> fetchPopularHosts() async {
    final body = await ApiClient.get(
      '/expert-profiles',
      query: {
        'popular': 'true',
        'pagination[pageSize]': pageSize,
        ...ListingApi.hostCardPopulate,
      },
    );
    final rows = Strapi.list(body);
    return HostPage.listable([
      for (var i = 0; i < rows.length; i++)
        HostCard.fromJson(rows[i], index: i),
    ]);
  }
}
