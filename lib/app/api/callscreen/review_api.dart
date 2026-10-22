import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'call_errors.dart';
import 'call_models.dart';

/// Expert reviews: left after a call (feedback sheet, Logs tab) and listed
/// on an expert profile.
abstract final class ReviewApi {
  static const expertPageSize = 10;

  /// Review left on one call (numeric call id), or null.
  static Future<Review?> fetchForCall(String callId) async {
    final body = await ApiClient.get(
      '/reviews',
      query: {'filters[call][id][\$eq]': callId, 'populate': '*'},
    );
    final rows = Strapi.list(Strapi.body(body));
    return rows.isEmpty ? null : Review(rows.first);
  }

  /// Newest first. [expertId] is the expert-profile documentId or numeric id.
  static Future<ReviewPage> fetchByExpert(
    String expertId, {
    int page = 1,
    int pageSize = expertPageSize,
  }) async {
    final id = expertId.trim();
    final filter = RegExp(r'^\d+$').hasMatch(id)
        ? 'filters[expert][id][\$eq]'
        : 'filters[expert][documentId][\$eq]';
    final body = await ApiClient.get(
      '/reviews',
      query: {
        filter: id,
        'populate[0]': 'user',
        'populate[1]': 'user.profilePic',
        'sort[0]': 'createdAt:desc',
        'pagination[page]': page,
        'pagination[pageSize]': pageSize,
      },
    );
    return ReviewPage.fromResponse(body, page: page);
  }

  /// Saves a review. Returns the saved row, with what was sent filling any
  /// field the response left out (the sheet shows it right away).
  static Future<Review> submit(ReviewInput input) async {
    if (J.str(input.expertId) == null) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: CallErrorKeys.expertUnresolved,
      );
    }
    if (!input.hasContent) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: CallErrorKeys.reviewEmpty,
      );
    }
    final body = await withCallFallback(
      CallErrorKeys.reviewFailed,
      () => ApiClient.post('/reviews', data: {'data': input.toJson()}),
    );
    final saved = Strapi.map(Strapi.body(body)) ?? const {};
    return Review({
      'rating': input.rating,
      'comments': input.comments,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      for (final e in saved.entries)
        if (e.value != null) e.key: e.value,
    });
  }
}

class ReviewInput {
  const ReviewInput({
    required this.expertId,
    required this.userId,
    required this.rating,
    this.comments = '',
    this.callId,
  });

  /// Expert-profile documentId (or id). Resolving it from the host's public
  /// user is the profile feature's job; null fails with
  /// [CallErrorKeys.expertUnresolved].
  final Object? expertId;

  /// Reviewer's public-user documentId (or id).
  final Object userId;

  /// 0–5 stars.
  final num rating;
  final String comments;

  /// Numeric id of the reviewed call.
  final Object? callId;

  /// RN review sheet: a star rating or a written comment is required.
  bool get hasContent => rating > 0 || comments.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'expert': expertId,
    'user': userId,
    'rating': rating,
    'comments': comments,
    'call': ?callId,
  };
}
