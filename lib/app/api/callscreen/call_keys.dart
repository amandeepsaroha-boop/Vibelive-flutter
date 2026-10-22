/// Query keys for calls, call history and reviews. Same key ⇒ same data type
/// everywhere.
abstract final class CallKeys {
  static const all = ['call'];

  /// Prefix of every history query (first page + further pages, all users).
  static const history = ['call', 'history'];

  /// Every history query of one user.
  static List<Object?> historyOf(String userDocumentId) => [
    ...history,
    userDocumentId,
  ];

  /// Page 1 (`CallHistoryPage`, persisted on disk).
  static List<Object?> historyFirstPage(String userDocumentId) => [
    ...historyOf(userDocumentId),
    'first',
  ];

  /// Pages 2+ (infinite query of `CallHistoryPage`).
  static List<Object?> historyMorePages(String userDocumentId) => [
    ...historyOf(userDocumentId),
    'more',
  ];

  static const status = ['call', 'status'];

  /// `CallStatus` of one call.
  static List<Object?> statusOf(String callId) => [...status, callId];

  static const reviews = ['call', 'reviews'];

  /// `Review?` left on one call.
  static List<Object?> callReview(String callId) => [
    ...reviews,
    'call',
    callId,
  ];

  /// Prefix of every expert's review list.
  static const expertReviewsAll = ['call', 'reviews', 'expert'];

  /// Paged reviews of one expert (infinite query of `ReviewPage`).
  static List<Object?> expertReviews(String expertId) => [
    ...expertReviewsAll,
    expertId,
  ];

  /// What a new or finished call changes: the call logs and its status.
  static List<List<Object?>> afterCallChange(String callId) => [
    history,
    statusOf(callId),
  ];
}
