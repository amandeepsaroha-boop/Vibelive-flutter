import 'package:flutter/foundation.dart' show immutable;

import '../../../core/network/strapi.dart';
import 'listing_models.dart';

/// `GET /search` response: `{results: {experts, categories,
/// category_and_location}}`. Ranking happens server-side; nothing is
/// re-scored here.
@immutable
class SearchResults {
  const SearchResults({
    this.experts = const [],
    this.categories = const [],
    this.categoryLocations = const [],
  });

  factory SearchResults.fromResponse(dynamic body) {
    final results = body is Map && body['results'] is Map
        ? body['results'] as Map
        : const {};
    // Plain JSON (not Strapi entities): rows are read as they are.
    List<JsonMap> rows(String key) => [
      for (final r in _list(results[key]))
        if (r is Map) Map<String, dynamic>.from(r),
    ];
    return SearchResults(
      experts: [for (final r in rows('experts')) SearchHost.fromJson(r)],
      categories: [for (final r in rows('categories')) SearchCategory(r)],
      categoryLocations: [
        for (final r in rows('category_and_location'))
          SearchCategoryLocation(r),
      ],
    );
  }

  final List<SearchHost> experts;
  final List<SearchCategory> categories;
  final List<SearchCategoryLocation> categoryLocations;

  bool get isEmpty =>
      experts.isEmpty && categories.isEmpty && categoryLocations.isEmpty;

  /// Expert-profile documentIds of the rows, for [HostBadges] enrichment.
  List<String> get expertDocumentIds => [
    for (final e in experts) ?e.documentId,
  ];

  /// Upgrades the rows with the batched verification read: `/search` returns
  /// `isVerified` but not the social flags that make a host an influencer.
  SearchResults withBadges(Map<String, HostBadges> badges) {
    if (badges.isEmpty) return this;
    return SearchResults(
      experts: [
        for (final e in experts)
          if (badges[e.documentId ?? ''] case final b?) e.withBadges(b) else e,
      ],
      categories: categories,
      categoryLocations: categoryLocations,
    );
  }

  static List<Object?> _list(Object? v) => v is List ? v : const [];
}

/// An expert row of `/search` (a summary: no gallery, city or social links;
/// open the profile through `ListingApi.findHost`).
@immutable
class SearchHost implements HostTraits {
  const SearchHost._({
    required this.raw,
    required this.documentId,
    required this.userDocumentId,
    required this.handler,
    required this.name,
    required this.tagline,
    required this.categories,
    required this.topics,
    required this.languages,
    required this.rating,
    required this.reviewCount,
    required this.isVerified,
    required this.instaVerified,
    required this.facebookVerified,
    required this.snapchatVerified,
    required this.profilePic,
    required this.voiceRate,
    required this.videoRate,
    required this.callMinutes,
  });

  static const defaultNameKey = 'listing:search.default_name';

  factory SearchHost.fromJson(JsonMap e) {
    List<String> names(Object? v, List<String> keys) => [
      if (v is List)
        for (final item in v)
          ?(item is String
              ? _nonEmpty(item)
              : item is Map
              ? _nonEmpty(_firstStr(item, keys))
              : null),
    ];
    final rates = e['rates'] is Map ? e['rates'] as Map : const {};
    final durations = e['durations'] is Map ? e['durations'] as Map : const {};
    return SearchHost._(
      raw: e,
      documentId: J.str(e['documentId']),
      userDocumentId: J.str(e['userDocumentId']),
      handler: J.str(e['handler']),
      name: J.str(e['name']) ?? '',
      tagline: J.str(e['tagline']) ?? '',
      categories: names(e['categories'], const ['name']),
      topics: names(e['topics'], const ['label', 'name']),
      languages: names(e['languages'], const ['name']),
      rating: _number(e['averageRating']),
      reviewCount: _number(e['reviewCount']).toInt(),
      isVerified: _truthy(e['isVerified']),
      instaVerified:
          _truthy(e['instaVerified']) || _truthy(e['insta_verified']),
      facebookVerified:
          _truthy(e['facebookVerified']) || _truthy(e['facebook_verified']),
      snapchatVerified:
          _truthy(e['snapchatVerified']) || _truthy(e['snapchat_verified']),
      profilePic: e['profilePic'] is Map
          ? Strapi.mediaFromAsset(e['profilePic'])
          : Strapi.mediaUrl(J.str(e['profilePic'])),
      voiceRate: _number(rates['voiceCallRate']),
      videoRate: _number(rates['videoCallRate']),
      callMinutes: _number(durations['TotalMin']),
    );
  }

  final JsonMap raw;

  /// Expert-profile documentId (what the full-profile lookup filters on).
  final String? documentId;
  final String? userDocumentId;
  final String? handler;

  /// Empty → [defaultNameKey].
  final String name;
  final String tagline;
  @override
  final List<String> categories;
  @override
  final List<String> topics;
  @override
  final List<String> languages;
  final double rating;
  final int reviewCount;
  final bool isVerified;
  final bool instaVerified;
  final bool facebookVerified;
  final bool snapchatVerified;
  final String? profilePic;
  final double voiceRate;
  final double videoRate;

  /// Minutes the host has actually spent on calls ("calls handled").
  final double callMinutes;

  @override
  List<String> get topicValues => const [];

  /// First category reads as the specialization line.
  @override
  String get specialization => categories.isEmpty ? '' : categories.first;

  /// First two categories joined, for the context line.
  String get categoryLabel => categories.take(2).join(' • ');

  /// Flags in the shape `VerificationBadge` reads (`expert:`).
  JsonMap get badgeFlags => {
    'isVerified': isVerified,
    'instaVerified': instaVerified,
    'facebookVerified': facebookVerified,
    'snapchatVerified': snapchatVerified,
  };

  SearchHost withBadges(HostBadges b) => SearchHost._(
    raw: raw,
    documentId: documentId,
    userDocumentId: userDocumentId,
    handler: handler,
    name: name,
    tagline: tagline,
    categories: categories,
    topics: topics,
    languages: languages,
    rating: rating,
    reviewCount: reviewCount,
    isVerified: b.verified,
    instaVerified: b.instaVerified,
    facebookVerified: b.facebookVerified,
    snapchatVerified: b.snapchatVerified,
    profilePic: profilePic,
    voiceRate: voiceRate,
    videoRate: videoRate,
    callMinutes: callMinutes,
  );

  static String? _firstStr(Map m, List<String> keys) {
    for (final k in keys) {
      final v = J.str(m[k]);
      if (v != null) return v;
    }
    return null;
  }
}

/// A category hit: tapping it re-runs the search with [name] (there is no
/// category screen).
@immutable
class SearchCategory {
  const SearchCategory(this.raw);

  final JsonMap raw;

  String? get documentId => J.str(raw['documentId']);
  String get name => J.str(raw['name']) ?? '';
  int? get callsCount => J.integer(raw['callsCount']);
}

/// A "category in location" hit. [label] may be empty: the UI then joins
/// [categoryName] and [locationName].
@immutable
class SearchCategoryLocation {
  const SearchCategoryLocation(this.raw);

  final JsonMap raw;

  String get label => J.str(raw['label']) ?? '';
  String get categoryName => J.str(Strapi.map(raw['category'])?['name']) ?? '';
  String get locationName => J.str(Strapi.map(raw['location'])?['name']) ?? '';

  /// What tapping the row searches for.
  String get query => categoryName.isNotEmpty ? categoryName : label;
}

bool _truthy(Object? v) => switch (v) {
  null => false,
  final bool b => b,
  final num n => n != 0 && !n.isNaN,
  final String s => s.isNotEmpty,
  _ => true,
};

double _number(Object? v) {
  final n = J.number(v);
  return n == null || !n.isFinite ? 0 : n;
}

String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
