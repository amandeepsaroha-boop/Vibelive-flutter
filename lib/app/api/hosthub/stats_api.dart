import '../../../core/network/api_client.dart';
import 'stats_models.dart';

/// Host dashboard statistics, pre-aggregated server-side.
abstract final class HostStatsApi {
  /// Filtered on the USER's documentId (`public_profile`), not the expert
  /// profile's. [HostStats.empty] when there is no row yet.
  static Future<HostStats> fetch(String userDocumentId) async {
    final body = await ApiClient.get(
      '/user-statistics',
      query: {
        'filters[public_profile][documentId][\$eq]': userDocumentId,
        'populate': '*',
      },
    );
    final rows = body is Map ? body['data'] : null;
    if (rows is! List || rows.isEmpty) return HostStats.empty;
    return HostStats.fromRow(rows.first);
  }
}
