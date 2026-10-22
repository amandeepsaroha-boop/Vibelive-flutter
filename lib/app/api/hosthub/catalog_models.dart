import '../../../core/config/env.dart';
import '../../../core/network/strapi.dart';

/// A language or category option (RN `normalizeLanguage` /
/// `normalizeCategory`). Rows without an id or a label are dropped.
class HostOption {
  const HostOption({
    this.id,
    this.documentId,
    required this.label,
    this.raw = const {},
  });

  final int? id;
  final String? documentId;
  final String label;
  final JsonMap raw;

  /// RN `value`: numeric id first, then documentId.
  Object? get value => id ?? documentId;

  /// Strapi v5 relation reference for `{connect: [...]}`, documentId first.
  JsonMap? get connectRef => documentId != null
      ? {'documentId': documentId}
      : (id != null ? {'id': id} : null);

  static HostOption? language(dynamic row) =>
      _from(row, const ['name', 'languageNames', 'language']);

  static HostOption? category(dynamic row) =>
      _from(row, const ['name', 'category']);

  static HostOption? _from(dynamic row, List<String> labelKeys) {
    final m = Strapi.map(row);
    if (m == null) return null;
    String? label;
    for (final k in labelKeys) {
      label ??= J.str(m[k]);
    }
    final option = HostOption(
      id: J.integer(m['id']),
      documentId: J.str(m['documentId']),
      label: (label ?? '').trim(),
      raw: m,
    );
    return option.value == null || option.label.isEmpty ? null : option;
  }

  /// RN `uniqueById`: first occurrence per id/documentId (merging pages).
  static List<HostOption> uniqueById(Iterable<HostOption> items) {
    final seen = <Object>{};
    return [
      for (final item in items)
        if (item.value != null && seen.add(item.value!)) item,
    ];
  }
}

/// Platform filter for `/categories` (RN `normalizePlatformFilter`): id wins,
/// then documentId, then a case-insensitive name match.
class CategoryPlatform {
  const CategoryPlatform({this.id, this.documentId, this.name = ''});

  final int? id;
  final String? documentId;
  final String name;

  /// From the user's populated `platform` relation.
  static CategoryPlatform? fromRelation(dynamic platform) {
    final m = Strapi.map(platform);
    if (m == null) return null;
    final p = CategoryPlatform(
      id: J.integer(m['id']),
      documentId: J.str(m['documentId']),
      name: (J.str(m['name']) ?? '').trim(),
    );
    return p.filter.isEmpty ? null : p;
  }

  /// From a bare value: digits are an id, anything else a documentId (RN
  /// rule, kept as is).
  static CategoryPlatform? parse(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(v)) return CategoryPlatform(id: int.parse(v));
    return CategoryPlatform(documentId: v, name: v);
  }

  /// RN default when the user has no platform: `CONFIG.APP_PLATFORM`.
  static CategoryPlatform get appDefault =>
      parse(Env.appPlatform) ?? const CategoryPlatform();

  Map<String, dynamic> get filter {
    if (id != null) return {'filters[platform][id][\$eq]': id};
    if (documentId != null) {
      return {'filters[platform][documentId][\$eq]': documentId};
    }
    if (name.isNotEmpty) return {'filters[platform][name][\$eqi]': name};
    return const {};
  }

  /// Stable, JSON-encodable query-key part.
  String get cacheKey => '${id ?? ''}:${documentId ?? ''}:$name';
}

/// One `/categories` page.
class CategoryPage {
  const CategoryPage({
    required this.items,
    required this.page,
    required this.pageSize,
    this.pagination,
  });

  final List<HostOption> items;
  final int page;
  final int pageSize;

  /// Raw `meta.pagination`, when the server sent it.
  final JsonMap? pagination;

  int? get pageCount => J.integer(pagination?['pageCount']);

  /// RN rule: trust `meta.pagination` when it has a page, otherwise "a full
  /// page means there may be more".
  bool get hasMore {
    final serverPage = J.integer(pagination?['page']) ?? 0;
    if (serverPage > 0) return serverPage < (pageCount ?? 0);
    return items.length >= pageSize;
  }
}
