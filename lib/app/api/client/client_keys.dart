/// Query keys for the signed-in user's profile area (Profile tab). Same key ⇒
/// same data type everywhere.
abstract final class ClientKeys {
  static const all = ['client'];

  /// Every user + expert read (mine and other people's).
  static const profiles = ['client', 'profile'];

  /// Persisted; see `useMyProfile`.
  static List<Object?> myProfile(String userDocumentId) => [
    ...profiles,
    'me',
    userDocumentId,
  ];

  static List<Object?> userWithExpert(String userDocumentId) => [
    ...profiles,
    'user',
    userDocumentId,
  ];

  static const geo = ['client', 'geo'];

  static List<Object?> countries({
    required String search,
    required int page,
    required int pageSize,
  }) => [...geo, 'countries', search, page, pageSize];

  static List<Object?> countryByName(String name) => [...geo, 'country', name];

  static List<Object?> states({
    required String? countryName,
    required String search,
    required int page,
    required int pageSize,
  }) => [...geo, 'states', countryName, search, page, pageSize];

  static List<Object?> districts({
    required String stateId,
    required String stateIdField,
    required String search,
    required int page,
    required int pageSize,
  }) => [...geo, 'districts', stateId, stateIdField, search, page, pageSize];

  static const blockedUsers = ['client', 'blocked-users'];

  static List<Object?> blockedUsersPage(
    String userDocumentId, {
    required int limit,
    required int offset,
  }) => [...blockedUsers, userDocumentId, limit, offset];

  static const favorites = ['client', 'favorites'];

  static List<Object?> favoritesOf(String userDocumentId) => [
    ...favorites,
    userDocumentId,
  ];

  static const gstDetails = ['client', 'gst-details'];

  static List<Object?> gstDetailsOf(String userDocumentId) => [
    ...gstDetails,
    userDocumentId,
  ];

  static const referral = ['client', 'referral'];

  static List<Object?> referralDashboard(String userDocumentId) => [
    ...referral,
    'dashboard',
    userDocumentId,
  ];

  static List<Object?> referralCode(String userDocumentId) => [
    ...referral,
    'code',
    userDocumentId,
  ];
}
