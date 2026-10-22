import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import 'catalog_models.dart';
import 'strapi_lookup.dart';

/// Reference data for the host profile editor: `/languages`, `/categories`.
abstract final class HostCatalogApi {
  static Future<List<HostOption>> fetchLanguages() async {
    final body = await ApiClient.get(
      '/languages',
      query: {'pagination[page]': 1, 'pagination[pageSize]': 250},
    );
    return [
      for (final row in StrapiLookup.rowsOf(body)) ?HostOption.language(row),
    ];
  }

  /// Categories of a platform, by name; [platform] defaults to this app's.
  static Future<CategoryPage> fetchCategoriesPage({
    int page = 1,
    int pageSize = 45,
    String search = '',
    CategoryPlatform? platform,
  }) async {
    final term = search.trim();
    final body = await ApiClient.get(
      '/categories',
      query: {
        'sort': 'name:asc',
        'pagination[page]': page,
        'pagination[pageSize]': pageSize,
        ...(platform ?? CategoryPlatform.appDefault).filter,
        if (term.isNotEmpty) 'filters[name][\$containsi]': term,
      },
    );
    return CategoryPage(
      items: [
        for (final row in StrapiLookup.rowsOf(body)) ?HostOption.category(row),
      ],
      page: page,
      pageSize: pageSize,
      pagination: Strapi.pagination(body),
    );
  }

  /// Every page (used once the host searches), deduped.
  static Future<List<HostOption>> fetchAllCategories({
    int pageSize = 45,
    CategoryPlatform? platform,
  }) async {
    final first = await fetchCategoriesPage(
      pageSize: pageSize,
      platform: platform,
    );
    final all = [...first.items];
    final totalPages = first.pageCount ?? 1;
    for (var page = 2; page <= totalPages; page++) {
      final next = await fetchCategoriesPage(
        page: page,
        pageSize: pageSize,
        platform: platform,
      );
      all.addAll(next.items);
    }
    final seen = <String>{};
    return [
      for (final c in all)
        if (seen.add('${c.id ?? ''}:${c.documentId ?? ''}:${c.label}')) c,
    ];
  }
}
