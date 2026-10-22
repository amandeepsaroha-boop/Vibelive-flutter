import '../../../core/query/query_hooks.dart';

/// Query keys for the host hub (a host managing their own profile).
/// Same key ⇒ same data type everywhere.
abstract final class HostHubKeys {
  static const all = ['hosthub'];

  /// Prefix of every host-profile read (by id and by user).
  static const profileAll = ['hosthub', 'profile'];
  static RawQueryKey profile(String expertId) => [
    'hosthub',
    'profile',
    'id',
    expertId,
  ];
  static RawQueryKey profileByUser(String userDocumentId) => [
    'hosthub',
    'profile',
    'user',
    userDocumentId,
  ];

  static const languages = ['hosthub', 'languages'];

  static const categoriesAll = ['hosthub', 'categories'];
  static RawQueryKey categoriesPage(
    String platform,
    int page,
    int pageSize,
    String search,
  ) => ['hosthub', 'categories', 'page', platform, page, pageSize, search];
  static RawQueryKey allCategories(String platform) => [
    'hosthub',
    'categories',
    'all',
    platform,
  ];

  static const imagesAll = ['hosthub', 'profile-images'];
  static RawQueryKey profileImages(String expertId) => [
    'hosthub',
    'profile-images',
    expertId,
  ];

  static const approvalAll = ['hosthub', 'approval'];
  static RawQueryKey latestApproval(String expertId) => [
    'hosthub',
    'approval',
    expertId,
  ];

  static const verificationAll = ['hosthub', 'verification'];
  static RawQueryKey latestVerification(String expertId) => [
    'hosthub',
    'verification',
    'latest',
    expertId,
  ];
  static RawQueryKey currentVerification(
    String expertId, {
    bool draft = false,
  }) => [
    'hosthub',
    'verification',
    'current',
    expertId,
    draft ? 'draft' : 'published',
  ];

  static const educationLevels = ['hosthub', 'education-levels'];

  static const statsAll = ['hosthub', 'stats'];
  static RawQueryKey stats(String userDocumentId) => [
    'hosthub',
    'stats',
    userDocumentId,
  ];

  static const expertise = ['hosthub', 'expertise'];

  /// Missing sections before approval (needs the expertise read).
  static RawQueryKey completion(String expertId) => [
    'hosthub',
    'profile',
    'completion',
    expertId,
  ];

  /// "Is this handle free?" (onboarding); [ownExpertId] '' for a new host.
  static RawQueryKey handleCheck(String handle, String ownExpertId) => [
    'hosthub',
    'handle',
    handle,
    ownExpertId,
  ];
}
