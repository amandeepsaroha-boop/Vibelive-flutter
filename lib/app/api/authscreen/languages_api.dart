import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import '../hosthub/catalog_models.dart';
import '../hosthub/strapi_lookup.dart';

/// The Languages collection (Strapi `api::language.language`, label
/// `languageNames`): what the onboarding language step offers.
///
/// Rows parse as the host editor's `HostOption.language`. The fetch is its
/// own, not `HostCatalogApi.fetchLanguages`: that one sends no sort and reads
/// a single 250-row page.
abstract final class LanguagesApi {
  static const pageSize = 100;

  /// Bound on the page loop, so a server that misreports `pageCount` cannot
  /// spin it forever.
  static const _maxPages = 20;

  /// Every language, A→Z by `languageNames`, all pages, first row per id.
  static Future<List<HostOption>> fetchAll() async {
    final all = <HostOption>[];
    for (var page = 1; page <= _maxPages; page++) {
      final body = await ApiClient.get(
        '/languages',
        query: {
          'sort': 'languageNames:asc',
          'pagination[page]': page,
          'pagination[pageSize]': pageSize,
        },
      );
      final rows = StrapiLookup.rowsOf(body);
      for (final row in rows) {
        final option = HostOption.language(row);
        if (option != null) all.add(option);
      }
      final pageCount = J.integer(Strapi.pagination(body)?['pageCount']);
      final last = pageCount == null
          ? rows.length < pageSize
          : page >= pageCount;
      if (rows.isEmpty || last) break;
    }
    return HostOption.uniqueById(all);
  }
}
