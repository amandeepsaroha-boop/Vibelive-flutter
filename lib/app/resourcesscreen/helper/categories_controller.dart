import 'package:flutter/foundation.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/log.dart';
import '../../api/hosthub/catalog_models.dart';
import '../../api/hosthub/profile_models.dart';
import '../../api/hosthub/profile_patch.dart';
import '../../api/resourcesscreen/host_categories_api.dart';
import '../../api/resourcesscreen/resources_queries.dart';

/// The Categories screen's list and selection (RN `CategoriesScreen`
/// state): pages of 45, everything once the host searches, at most
/// [maxSelected] picks, picks listed first.
class CategoriesController extends ChangeNotifier {
  CategoriesController({this.pageSize = 45});

  static const maxSelected = 10;
  final int pageSize;

  CategoryPlatform? _platform;
  var _items = <HostOption>[];
  var _page = 1;
  var _hasMore = false;
  var _loadedAll = false;
  var _loadingMore = false;
  var _loadingAll = false;
  var _query = '';
  var _seeded = false;

  /// Picked options by [HostOption.value], in pick order.
  final _selected = <Object, HostOption>{};

  bool get seeded => _seeded;
  bool get busy => _loadingMore || _loadingAll;
  String get query => _query;
  int get selectedCount => _selected.length;
  bool isSelected(HostOption o) => _selected.containsKey(o.value);

  /// First page + saved picks; later calls are ignored.
  void seed(HostCategoriesSetup setup, CategoryPage first) {
    if (_seeded) return;
    _seeded = true;
    _platform = setup.platform;
    _items = first.items;
    _page = 1;
    _hasMore = first.hasMore;
    _loadedAll = !_hasMore;
    for (final o in setup.selected) {
      if (_selected.length < maxSelected && o.value != null) {
        _selected[o.value!] = o;
      }
    }
    notifyListeners();
  }

  /// Next page (not while searching). Failures keep the list usable.
  Future<void> loadMore() async {
    if (!_seeded || busy || !_hasMore || _query.trim().isNotEmpty) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final next = await ensureCategoriesPage(
        page: _page + 1,
        pageSize: pageSize,
        platform: _platform,
      );
      _items = HostOption.uniqueById([..._items, ...next.items]);
      _page++;
      _hasMore = next.hasMore;
      if (!_hasMore) _loadedAll = true;
    } catch (e) {
      Log.w('Categories', 'load more failed: $e');
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Search runs over every category, so the first search loads them all.
  void setQuery(String value) {
    _query = value;
    notifyListeners();
    if (value.trim().isNotEmpty) _loadAll();
  }

  Future<void> _loadAll() async {
    if (_loadedAll || _loadingAll) return;
    _loadingAll = true;
    notifyListeners();
    try {
      _items = await ensureAllCategories(platform: _platform);
      _hasMore = false;
      _loadedAll = true;
    } catch (e) {
      Log.w('Categories', 'load all failed: $e');
    } finally {
      _loadingAll = false;
      notifyListeners();
    }
  }

  /// Adds or removes; an 11th pick is ignored.
  void toggle(HostOption o) {
    final v = o.value;
    if (v == null) return;
    if (_selected.remove(v) == null) {
      if (_selected.length >= maxSelected) return;
      _selected[v] = o;
    }
    notifyListeners();
  }

  /// Matching options, picks first, each group A→Z.
  List<HostOption> get visible {
    final q = _query.trim().toLowerCase();
    final base = q.isEmpty
        ? _items
        : _items.where((o) => o.label.toLowerCase().contains(q));
    int byLabel(HostOption a, HostOption b) => a.label.compareTo(b.label);
    final chosen = base.where(isSelected).toList()..sort(byLabel);
    final rest = base.where((o) => !isSelected(o)).toList()..sort(byLabel);
    return [...chosen, ...rest];
  }

  /// `PUT /expert-profiles/:id` body: numeric id when known (RN), else the
  /// documentId.
  HostProfilePatch get patch => HostProfilePatch({
    'categories': [
      for (final o in _selected.values)
        o.id != null ? {'id': o.id} : {'documentId': o.documentId},
    ],
  });

  /// RN `nextStepFromMissing` on the saved profile: schedule, then call
  /// rates, else approval.
  static String nextRoute(HostProfile? saved) =>
      switch (saved?.completion().nextSection) {
        HostProfileSection.schedule => AppRoutes.schedule,
        HostProfileSection.rates => AppRoutes.callRates,
        _ => AppRoutes.approval,
      };
}
