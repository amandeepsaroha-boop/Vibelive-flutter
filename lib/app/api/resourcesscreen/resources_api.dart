import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'resources_models.dart';

/// `/page-contents`: CMS pages listed in the Profile → Resources menu, and a
/// single page by slug (About, Support, menu entries).
abstract final class ResourcesApi {
  /// Slugs RN never listed in the menu.
  static const _hiddenFromMenu = {'terms-and-conditions'};

  /// Pages flagged `show_in_menu`, oldest first.
  static Future<List<MenuPage>> fetchMenuPages() async {
    final body = await ApiClient.get(
      '/page-contents',
      query: {
        r'filters[show_in_menu][$eq]': true,
        'publicationState': 'live',
        'sort[0]': 'createdAt:asc',
      },
    );
    return [
      for (final row in Strapi.list(body))
        if (MenuPage.fromRow(row) case final page
            when page.slug.isNotEmpty && !_hiddenFromMenu.contains(page.slug))
          page,
    ];
  }

  /// [MenuPage.exists] is false when no live page has [slug].
  static Future<MenuPage> fetchPageBySlug(String slug) async {
    final clean = slug.trim();
    if (clean.isEmpty) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'resources:errors.missing_page',
      );
    }
    final rows = Strapi.list(
      await ApiClient.get(
        '/page-contents',
        query: {
          r'filters[slug][$eq]': clean,
          'publicationState': 'live',
          'pagination[limit]': 1,
        },
      ),
    );
    return rows.isEmpty
        ? MenuPage.missing(clean)
        : MenuPage.fromRow(rows.first);
  }
}
