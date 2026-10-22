import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import 'banner_models.dart';

/// `/unlocked-milestones`: achievements the user has not seen yet. New ones
/// also arrive live as `milestone_unlocked` pushes
/// ([UnlockedMilestone.fromPush]).
abstract final class MilestoneApi {
  static const _milestoneFields = [
    'documentId',
    'milestone_key',
    'title',
    'subtitle',
    'badgeLabel',
    'tierLabel',
    'iconName',
    'iconFamily',
    'primaryColor',
    'gradientColors',
  ];

  static Future<List<UnlockedMilestone>> fetchUnviewed(
    String userDocumentId,
  ) async {
    final id = userDocumentId.trim();
    if (id.isEmpty) return const [];
    final body = await ApiClient.get(
      '/unlocked-milestones',
      query: {
        r'filters[user][documentId][$eq]': id,
        r'filters[isViewed][$eq]': 'false',
        for (final (i, field) in _milestoneFields.indexed)
          'populate[milestone][fields][$i]': field,
      },
    );
    return [
      for (final row in Strapi.list(body)) UnlockedMilestone.fromRow(row),
    ];
  }

  /// No-op without a document id (a push that carried none).
  static Future<void> markViewed(String unlockedMilestoneDocumentId) async {
    final id = unlockedMilestoneDocumentId.trim();
    if (id.isEmpty) return;
    await ApiClient.put(
      '/unlocked-milestones/${Uri.encodeComponent(id)}',
      data: {
        'data': {'isViewed': true},
      },
    );
  }
}
