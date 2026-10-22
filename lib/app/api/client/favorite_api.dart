import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'client_models.dart';

/// `/favorites`: the user's favourite hosts.
abstract final class FavoriteApi {
  /// Newest first, one row per host (max 100, like RN).
  static Future<List<FavoriteExpert>> fetchFavorites(
    String userDocumentId,
  ) async {
    final body = await ApiClient.get(
      '/favorites',
      query: {
        r'filters[users][documentId][$eq]': userDocumentId,
        'populate[experts][populate][user][populate]': 'profilePic',
        'sort[0]': 'createdAt:desc',
        'pagination[page]': 1,
        'pagination[pageSize]': 100,
      },
    );
    return FavoriteExpert.dedupe(Strapi.list(body).map(FavoriteExpert.fromRow));
  }

  /// Idempotent: returns the existing row when the host is already a
  /// favourite.
  static Future<FavoriteExpert> addFavorite({
    required String userDocumentId,
    required String expertDocumentId,
  }) async {
    if (userDocumentId.isEmpty || expertDocumentId.isEmpty) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'client:errors.missing_user',
      );
    }
    final existing = Strapi.list(
      await ApiClient.get(
        '/favorites',
        query: {
          r'filters[users][documentId][$eq]': userDocumentId,
          r'filters[experts][documentId][$eq]': expertDocumentId,
          'pagination[page]': 1,
          'pagination[pageSize]': 1,
        },
      ),
    );
    if (existing.isNotEmpty) return FavoriteExpert.fromRow(existing.first);

    final body = await ApiClient.post(
      '/favorites',
      data: {
        'data': {
          'users': [userDocumentId],
          'experts': [expertDocumentId],
        },
      },
    );
    return FavoriteExpert.fromRow(Strapi.map(Strapi.body(body)) ?? const {});
  }

  /// Deletes by favourite id; RN fell back to the expert id when that fails.
  static Future<void> removeFavorite({
    String? favoriteId,
    String? expertId,
  }) async {
    final hasExpert = expertId != null && expertId.isNotEmpty;
    if (favoriteId != null && favoriteId.isNotEmpty) {
      try {
        await ApiClient.delete('/favorites/${Uri.encodeComponent(favoriteId)}');
        return;
      } on ApiException {
        if (!hasExpert) rethrow;
      }
    }
    if (!hasExpert) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'client:errors.missing_favorite',
      );
    }
    await ApiClient.delete('/favorites/${Uri.encodeComponent(expertId)}');
  }
}
