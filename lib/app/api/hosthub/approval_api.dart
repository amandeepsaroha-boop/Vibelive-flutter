import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import 'approval_models.dart';
import 'strapi_lookup.dart';

/// Approval requests (`/expert-profile-approvals`) and the go-live notice.
abstract final class HostApprovalApi {
  static const _endpoint = '/expert-profile-approvals';

  /// Requests are saved as drafts (nothing publishes them) and a plain read
  /// returns only published rows, so an existing request looked missing and
  /// hosts filed duplicates. Read both, keep the most recently changed; a
  /// failed read throws rather than look like "no request".
  static Future<ApprovalRecord?> fetchLatest(String expertId) async {
    final filters = StrapiLookup.relationFilters('expert_profile', expertId);
    final [draft, published] = await Future.wait([
      StrapiLookup.fetchLatest(_endpoint, filters, query: {'status': 'draft'}),
      StrapiLookup.fetchLatest(_endpoint, filters),
    ]);
    final d = ApprovalRecord.from(draft);
    final p = ApprovalRecord.from(published);
    if (d == null) return p;
    if (p == null) return d;
    return p.changedAt >= d.changedAt ? p : d;
  }

  static Future<ApprovalRecord?> create(String expertId) async =>
      ApprovalRecord.from(
        Strapi.body(
          await ApiClient.post(
            _endpoint,
            data: {
              'data': {'expert_profile': expertId},
            },
          ),
        ),
      );

  /// Admin e-mail when a host goes live (CE frontend parity).
  static Future<dynamic> notifyAdminOnboarded({
    required String expertId,
    String? expertName,
    String? expertEmail,
  }) => ApiClient.post(
    '/notify-admin-expert-onboarded',
    data: {
      'expertName': (expertName ?? '').isEmpty ? 'Expert' : expertName,
      'expertEmail': expertEmail ?? '',
      'expertId': expertId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    },
  );
}
