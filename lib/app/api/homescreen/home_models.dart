import 'package:flutter/foundation.dart' show immutable;

import '../../../core/network/strapi.dart';
import '../listingflow/filter_models.dart';
import '../listingflow/listing_models.dart';

/// One page of the Discover feed.
@immutable
class HostPage {
  const HostPage({
    required this.page,
    required this.hosts,
    required this.hasMore,
    this.total,
  });

  factory HostPage.fromResponse(
    dynamic body, {
    required int page,
    required int pageSize,
  }) {
    final rows = Strapi.list(body);
    final meta = Strapi.pagination(body);
    final current = J.integer(meta?['page']);
    final count = J.integer(meta?['pageCount']);
    final total = J.integer(meta?['total']);
    return HostPage(
      page: page,
      hosts: [
        for (var i = 0; i < rows.length; i++)
          HostCard.fromJson(rows[i], index: (page - 1) * pageSize + i),
      ],
      // Without pagination meta, a full page means there may be more.
      hasMore: current != null && count != null
          ? current < count
          : rows.length >= pageSize,
      total: total,
    );
  }

  final int page;
  final List<HostCard> hosts;
  final bool hasMore;

  /// Hosts across all pages (pagination meta), when the server says.
  final int? total;

  /// The feed as shown: pages in order, one card per expert profile (a host
  /// can shift between pages while scrolling), rows without any id dropped.
  static List<HostCard> merge(Iterable<HostPage> pages) =>
      listable([for (final p in pages) ...p.hosts]);

  /// [merge]'s rules for a single list (e.g. Popular).
  static List<HostCard> listable(Iterable<HostCard> hosts) {
    final seen = <String>{};
    return [
      for (final h in hosts)
        if (J.str(h.raw['documentId']) ?? J.str(h.raw['id']) case final key?)
          if (seen.add(key) &&
              (h.userDocumentId != null || h.documentId != null))
            h,
    ];
  }
}

enum DiscoverTabKind { all, popular, topic }

/// The Discover tab strip: All, Popular (server-ranked), then one tab per
/// support topic.
@immutable
class DiscoverTab {
  const DiscoverTab._(this.kind, [this.label = '']);

  /// A topic tab, matched by option value first, then by [label].
  const DiscoverTab.topic(String label) : this._(DiscoverTabKind.topic, label);

  static const all = DiscoverTab._(DiscoverTabKind.all);
  static const popular = DiscoverTab._(DiscoverTabKind.popular);

  /// RN tab names, also accepted in the `topic` route param.
  static const _allName = 'All';
  static const _popularName = 'Popular';

  final DiscoverTabKind kind;
  final String label;

  bool get isAll => kind == DiscoverTabKind.all;
  bool get isPopular => kind == DiscoverTabKind.popular;
  bool get isTopic => kind == DiscoverTabKind.topic;

  /// Tab pinned by the `topic` route param, or null (stay on All).
  static DiscoverTab? fromParam(String? topic) {
    final t = (topic ?? '').trim();
    return t.isEmpty || t == _allName || t == _popularName
        ? null
        : DiscoverTab.topic(t);
  }

  /// i18n key of the title; a topic tab shows [label] instead.
  String? get titleKey => switch (kind) {
    DiscoverTabKind.all => 'home:tabs.all',
    DiscoverTabKind.popular => 'home:tabs.popular',
    DiscoverTabKind.topic => null,
  };

  /// i18n key of the empty state.
  String get emptyKey => switch (kind) {
    DiscoverTabKind.all => 'home:empty.all',
    DiscoverTabKind.popular => 'home:empty.popular',
    DiscoverTabKind.topic => 'home:empty.topic',
  };

  /// Whether [host] belongs on this tab. [topics] = the strip's topics
  /// (support topics, or [SupportTopic.fromHosts] when those are missing).
  bool matches(HostCard host, List<SupportTopic> topics) {
    if (!isTopic) return true;
    final value = topics
        .where((t) => sameText(t.label, label))
        .firstOrNull
        ?.value;
    return (value != null &&
            value.isNotEmpty &&
            host.topicValues.contains(value)) ||
        host.topics.any((t) => sameText(t, label));
  }

  @override
  bool operator ==(Object other) =>
      other is DiscoverTab && other.kind == kind && other.label == label;

  @override
  int get hashCode => Object.hash(kind, label);
}
