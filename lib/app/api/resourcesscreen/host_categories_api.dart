import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../hosthub/catalog_models.dart';

/// What the Categories screen starts from: the host's saved categories and
/// the platform the category list is filtered by.
class HostCategoriesSetup {
  const HostCategoriesSetup({
    required this.expertId,
    required this.selected,
    this.platform,
  });

  /// documentId first (RN `expert.documentId || expert.id`).
  final String expertId;
  final List<HostOption> selected;

  /// Null ⇒ the app's platform.
  final CategoryPlatform? platform;
}

/// `/public-users/:id` with the user's platform and the expert's
/// categories (RN `fetchUserWithExpert`, plus the `categories` relation the
/// RN screen read but never populated).
abstract final class HostCategoriesApi {
  static const _populate = {
    'populate[platform]': 'true',
    'populate[expert][populate][categories]': 'true',
  };

  static Future<HostCategoriesSetup> fetch(String userDocumentId) async {
    JsonMap? user;
    try {
      user = Strapi.map(
        Strapi.body(
          await ApiClient.get(
            '/public-users/${Uri.encodeComponent(userDocumentId)}',
            query: _populate,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      // Some deployments resolve a documentId only through list filters.
      final rows = Strapi.list(
        await ApiClient.get(
          '/public-users',
          query: {
            r'filters[documentId][$eq]': userDocumentId,
            'pagination[page]': 1,
            'pagination[pageSize]': 1,
            ..._populate,
          },
        ),
      );
      user = rows.isEmpty ? null : rows.first;
    }
    final expert = Strapi.map(user?['expert']);
    final expertId = J.str(expert?['documentId']) ?? J.str(expert?['id']);
    if (expert == null || expertId == null) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'resources:errors.no_host',
      );
    }
    return HostCategoriesSetup(
      expertId: expertId,
      platform: CategoryPlatform.fromRelation(user?['platform']),
      selected: [
        for (final row in Strapi.list(expert['categories']))
          ?HostOption.category(row),
      ],
    );
  }
}
