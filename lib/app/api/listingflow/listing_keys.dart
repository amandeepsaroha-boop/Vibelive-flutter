/// Query keys for browsing other hosts. Same key ⇒ same data type everywhere.
abstract final class ListingKeys {
  static const all = ['listing'];

  /// `List<HostCard>`.
  static List<Object?> hosts(Map<String, dynamic> query) => [
    'listing',
    'hosts',
    query,
  ];

  /// `Map<String, …>`: every full host card of the session (`HostIndex`).
  static const hostIndex = ['listing', 'host-index'];

  /// `int` (cards put in the host index) of one batched warm-up read.
  static List<Object?> warmHosts(String by, List<String> ids) => [
    'listing',
    'warm-hosts',
    by,
    ids,
  ];

  /// `HostCard` (search-hit ladder).
  static List<Object?> host({
    String? expertDocumentId,
    String? userDocumentId,
    String? handler,
  }) => ['listing', 'host', expertDocumentId, userDocumentId, handler];

  /// `HostCard` (shared link).
  static List<Object?> hostByLink(String targetId, bool isOwnProfile) => [
    'listing',
    'host-link',
    targetId,
    isOwnProfile,
  ];

  /// `HostCard` (call-log row / nudge profile to open).
  static List<Object?> profile({
    String? userDocumentId,
    String? userId,
    String? expertDocumentId,
    bool own = false,
  }) => ['listing', 'profile', userDocumentId, userId, expertDocumentId, own];

  /// `HostCard` (callback nudge; minimal populate).
  static List<Object?> callbackHost({
    String? expertDocumentId,
    String? userId,
  }) => ['listing', 'host-callback', expertDocumentId, userId];

  /// Prefix of every search query.
  static const search = ['listing', 'search'];

  /// `SearchResults`.
  static List<Object?> searchQuery(String query, int limit) => [
    ...search,
    query,
    limit,
  ];

  /// `Map<String, HostCard>`: full cards of search hits, by expert-profile
  /// documentId.
  static List<Object?> searchHosts(List<String> expertDocumentIds) => [
    'listing',
    'search-hosts',
    expertDocumentIds,
  ];
}
