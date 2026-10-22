/// Query keys for banners and the achievement modal.
abstract final class BannerKeys {
  static const all = ['banner'];
  static const milestones = ['banner', 'milestones'];

  static List<Object?> unviewedMilestones(String userDocumentId) => [
    ...milestones,
    'unviewed',
    userDocumentId,
  ];
}
