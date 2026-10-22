/// Query keys for CMS pages. Same key ⇒ same data type everywhere.
abstract final class ResourcesKeys {
  static const all = ['resources'];

  /// Persisted; see `useMenuPages`.
  static const menuPages = ['resources', 'menu-pages'];

  static const pages = ['resources', 'page'];
  static List<Object?> page(String slug) => [...pages, slug];

  /// The Categories screen's starting point (my categories + platform).
  static const hostCategoriesAll = ['resources', 'host-categories'];
  static List<Object?> hostCategories(String userDocumentId) => [
    ...hostCategoriesAll,
    userDocumentId,
  ];
}
