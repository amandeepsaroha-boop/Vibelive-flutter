import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'client_models.dart';
import 'profile_api.dart';

/// The user's referral code, who joined with it, and the share counter.
abstract final class ReferralApi {
  static Future<ReferralDashboard> fetchDashboard(
    String userDocumentId,
  ) async => dashboardFor(
    await ProfileApi.fetchUserWithMenuRelations(userDocumentId),
  );

  /// The dashboard from the user read with menu relations
  /// ([ProfileApi.fetchUserWithMenuRelations], shared with the invite card
  /// and GST) plus who joined with the code.
  static Future<ReferralDashboard> dashboardFor(JsonMap? user) async {
    final code = ReferralDashboard.codeFrom(user);
    var joined = const <JoinedUser>[];
    if (code.isNotEmpty) {
      try {
        final body = await ApiClient.get(
          '/public-users',
          query: {
            r'filters[referrerCode][$eq]': code,
            'populate[profilePic]': true,
            'sort': 'createdAt:desc',
            'pagination[page]': 1,
            'pagination[pageSize]': 100,
          },
        );
        joined = [for (final row in Strapi.list(body)) JoinedUser.fromRow(row)];
      } on ApiException {
        // Deliberate (RN): the code and counters still render without the
        // list of joined users.
        joined = const [];
      }
    }
    return ReferralDashboard.fromUser(user, joined);
  }

  /// Bumps the share counter of [code]; returns the new count when the
  /// backend sends it. Not retried: a retry could count one share twice.
  static Future<int?> trackShare(String code, ReferralShareType type) async {
    if (code.trim().isEmpty) return null;
    final body = await ApiClient.get(
      '/referral/${Uri.encodeComponent(code)}/copy',
      query: {'type': type.marker},
      retry: false,
    );
    return J.integer(Strapi.map(Strapi.body(body))?['copyCount']);
  }
}

/// Which funnel a share belongs to; mirrors the `?r=` marker of the link.
enum ReferralShareType {
  /// Referral screen (`?r=r`).
  referral('r'),

  /// Invite card / profile invite (`?r=i`).
  invite('i');

  const ReferralShareType(this.marker);
  final String marker;
}
