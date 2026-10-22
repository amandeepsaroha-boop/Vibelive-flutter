import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/session/session_store.dart';
import '../hosthub/catalog_api.dart';
import '../hosthub/catalog_models.dart';
import '../hosthub/hosthub_keys.dart';
import 'host_categories_api.dart';
import 'resources_api.dart';
import 'resources_keys.dart';
import 'resources_models.dart';

/// Dynamic Resources menu entries, kept on disk so the menu is complete
/// instantly on launch.
QueryResult<List<MenuPage>, ApiException> useMenuPages(BuildContext context) =>
    usePersistedQuery<List<MenuPage>>(
      ResourcesKeys.menuPages,
      ResourcesApi.fetchMenuPages,
      context: context,
      staleDuration: StaleTime.medium,
      toJson: _pagesToJson,
      fromJson: _pagesFromJson,
    );

/// Outside widgets (prime after login).
Future<List<MenuPage>> ensureMenuPages() =>
    queryCache.fetchQuery<List<MenuPage>>(ResourcesKeys.menuPages, () async {
      final pages = await ResourcesApi.fetchMenuPages();
      QueryPersist.write(ResourcesKeys.menuPages, _pagesToJson(pages));
      return pages;
    }, staleDuration: StaleTime.medium);

/// One page by slug. Check [MenuPage.exists]: for `support`, a missing page
/// falls back to [SupportContact.fromAppConfig] (use `useAppConfig`).
QueryResult<MenuPage, ApiException> useDynamicPage(
  BuildContext context,
  String slug, {
  bool enabled = true,
}) {
  final clean = slug.trim();
  return useApiQuery<MenuPage>(
    ResourcesKeys.page(clean),
    () => ResourcesApi.fetchPageBySlug(clean),
    context: context,
    enabled: enabled && clean.isNotEmpty,
    staleDuration: StaleTime.medium,
  );
}

/// The signed-in host's categories and platform (Categories screen).
QueryResult<HostCategoriesSetup, ApiException> useHostCategoriesSetup(
  BuildContext context,
) {
  final session = useValueListenable(SessionStore.instance);
  final id = session.userDocumentId ?? '';
  return useApiQuery<HostCategoriesSetup>(
    ResourcesKeys.hostCategories(id),
    () => HostCategoriesApi.fetch(id),
    context: context,
    enabled: id.isNotEmpty,
    staleDuration: StaleTime.none,
  );
}

/// One `/categories` page, through the host hub's cache (same key, same
/// data as `useHostCategoriesPage`).
Future<CategoryPage> ensureCategoriesPage({
  required int page,
  int pageSize = 45,
  CategoryPlatform? platform,
}) {
  final p = platform ?? CategoryPlatform.appDefault;
  return queryCache.fetchQuery<CategoryPage>(
    HostHubKeys.categoriesPage(p.cacheKey, page, pageSize, ''),
    () => HostCatalogApi.fetchCategoriesPage(
      page: page,
      pageSize: pageSize,
      platform: p,
    ),
    staleDuration: StaleTime.static,
  );
}

/// Every category (the host started searching).
Future<List<HostOption>> ensureAllCategories({CategoryPlatform? platform}) {
  final p = platform ?? CategoryPlatform.appDefault;
  return queryCache.fetchQuery<List<HostOption>>(
    HostHubKeys.allCategories(p.cacheKey),
    () => HostCatalogApi.fetchAllCategories(platform: p),
    staleDuration: StaleTime.static,
  );
}

Object? _pagesToJson(List<MenuPage> pages) => [
  for (final p in pages) p.toJson(),
];

List<MenuPage> _pagesFromJson(Object? json) => [
  for (final p in json! as List) MenuPage.fromJson(p),
];
