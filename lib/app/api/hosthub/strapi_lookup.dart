import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';

/// "Latest row linked to X" reads shared by approvals, verifications and the
/// host-profile fallbacks (RN `buildFilterCandidates` /
/// `fetchLatestByCandidates` / `fetchManyByCandidates`).
abstract final class StrapiLookup {
  static final _digits = RegExp(r'^\d+$');

  static bool isNumericId(String id) => _digits.hasMatch(id.trim());

  /// Filters to try, in order, for a relation. A non-numeric documentId must
  /// never reach `[id][$eq]`: Postgres throws on the integer cast.
  static List<Map<String, dynamic>> relationFilters(
    String relation,
    String id,
  ) => [
    if (isNumericId(id)) {'filters[$relation][id][\$eq]': id},
    {'filters[$relation][documentId][\$eq]': id},
  ];

  /// Same rule for the record's own id.
  static List<Map<String, dynamic>> ownIdFilters(String id) => [
    if (isNumericId(id)) {'filters[id][\$eq]': id},
    {'filters[documentId][\$eq]': id},
  ];

  /// Newest row (by `createdAt`) for the first filter that finds one.
  static Future<JsonMap?> fetchLatest(
    String endpoint,
    List<Map<String, dynamic>> filters, {
    Map<String, dynamic> query = const {},
  }) async {
    for (final filter in filters) {
      final body = await ApiClient.get(
        endpoint,
        query: {
          ...filter,
          ...query,
          'sort[0]': 'createdAt:desc',
          'pagination[limit]': 1,
        },
      );
      final rows = rowsOf(body);
      if (rows.isNotEmpty) return rows.first;
    }
    return null;
  }

  /// Rows for every filter (most recently changed first), deduped by
  /// documentId/id.
  static Future<List<JsonMap>> fetchMany(
    String endpoint,
    List<Map<String, dynamic>> filters, {
    int limit = 25,
  }) async {
    final seen = <String>{};
    final rows = <JsonMap>[];
    for (final filter in filters) {
      final body = await ApiClient.get(
        endpoint,
        query: {
          ...filter,
          'sort[0]': 'updatedAt:desc',
          'sort[1]': 'createdAt:desc',
          'pagination[limit]': limit,
        },
      );
      for (final row in rowsOf(body)) {
        final key = J.str(row['documentId']) ?? J.str(row['id']);
        if (key != null && seen.add(key)) rows.add(row);
      }
    }
    return rows;
  }

  /// The `data` rows of a list response, unwrapped (v4 or v5).
  static List<JsonMap> rowsOf(dynamic body) => Strapi.list(Strapi.body(body));
}
