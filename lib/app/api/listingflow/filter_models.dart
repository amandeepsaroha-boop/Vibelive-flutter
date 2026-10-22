import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../../../core/network/strapi.dart';
import 'listing_models.dart';

/// Case- and space-insensitive equality used by every listing filter.
bool sameText(String? a, String? b) =>
    (a ?? '').trim().toLowerCase() == (b ?? '').trim().toLowerCase();

/// Language (multi) + topic (single) filter of Discover and search. Applied
/// client-side over what is loaded.
@immutable
class HostFilter {
  const HostFilter({this.languages = const [], this.topic});

  static const none = HostFilter();

  final List<String> languages;
  final String? topic;

  bool get hasTopic => (topic ?? '').isNotEmpty;
  bool get isActive => languages.isNotEmpty || hasTopic;

  /// Badge count on the filter button.
  int get count => languages.length + (hasTopic ? 1 : 0);

  bool matches(HostTraits host) {
    if (languages.isNotEmpty) {
      final wanted = {for (final l in languages) l.trim().toLowerCase()};
      if (!host.languages.any((l) => wanted.contains(l.trim().toLowerCase()))) {
        return false;
      }
    }
    if (hasTopic) {
      final t = topic;
      return host.topics.any((x) => sameText(x, t)) ||
          host.topicValues.any((x) => sameText(x, t)) ||
          sameText(host.specialization, t) ||
          host.categories.any((x) => sameText(x, t));
    }
    return true;
  }

  /// [topic] null clears it.
  HostFilter withTopic(String? topic) =>
      HostFilter(languages: languages, topic: topic);

  HostFilter withoutLanguage(String language) => HostFilter(
    languages: [
      for (final l in languages)
        if (!sameText(l, language)) l,
    ],
    topic: topic,
  );

  @override
  bool operator ==(Object other) =>
      other is HostFilter &&
      other.topic == topic &&
      listEquals(other.languages, languages);

  @override
  int get hashCode => Object.hash(topic, Object.hashAll(languages));
}

/// One option of the interests question "What do you need support with?":
/// Discover's topic tabs (VibeCalling has no category collection).
@immutable
class SupportTopic {
  const SupportTopic({required this.label, required this.value});

  final String label;
  final String value;

  /// Options of the `support_topic` question of an `/interests/form`
  /// payload (raw or normalized), in admin order, unique by label.
  static List<SupportTopic> fromForm(Object? form) {
    final questions = Strapi.map(form)?['questions'];
    if (questions is! List) return const [];
    final question = questions.whereType<Map>().where(
      (q) => (J.str(q['key']) ?? '').trim() == SupportTopicKey.question,
    );
    if (question.isEmpty) return const [];
    final options = question.first['options'];
    if (options is! List) return const [];
    final seen = <String>{};
    final out = <SupportTopic>[];
    for (final o in options.whereType<Map>()) {
      final topic = _topic(o);
      if (topic != null && seen.add(topic.label)) out.add(topic);
    }
    return out;
  }

  /// Fallback when the form cannot be loaded: the topics the loaded hosts
  /// carry, so the strip never comes up empty while hosts are listed.
  static List<SupportTopic> fromHosts(Iterable<HostCard> hosts) {
    final seen = <String, SupportTopic>{};
    for (final h in hosts) {
      for (var i = 0; i < h.topics.length; i++) {
        final label = h.topics[i];
        seen.putIfAbsent(
          label,
          () => SupportTopic(
            label: label,
            value: i < h.topicValues.length ? h.topicValues[i] : '',
          ),
        );
      }
    }
    return seen.values.toList();
  }

  static SupportTopic? _topic(Map o) {
    final value = (J.str(o['value']) ?? '').trim();
    final label = (J.str(o['label']) ?? value).trim();
    return label.isEmpty || value.isEmpty
        ? null
        : SupportTopic(label: label, value: value);
  }

  @override
  bool operator ==(Object other) =>
      other is SupportTopic && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// Choices offered by the filter sheet (RN `fetchFilterOptions` plus what
/// the loaded hosts carry). Sorted and de-duplicated.
@immutable
class FilterOptions {
  const FilterOptions({this.languages = const [], this.topics = const []});

  /// [languages]: `/languages` rows (`label`/`name`/`language`) or strings.
  /// [topics]: support topics. Languages never come from interest answers.
  factory FilterOptions.fromSources({
    Iterable<Object?> languages = const [],
    Iterable<SupportTopic> topics = const [],
  }) => FilterOptions(
    languages: _sorted([
      for (final l in languages)
        cleanLanguageName(
          l is Map
              ? J.str(l['label']) ?? J.str(l['name']) ?? J.str(l['language'])
              : J.str(l),
        ),
    ]),
    topics: _sorted([for (final t in topics) t.label.trim()]),
  );

  final List<String> languages;
  final List<String> topics;

  /// Adds the languages and topics of [hosts]. Search also offers their
  /// categories and specialization ([includeCategories]).
  FilterOptions withHosts(
    Iterable<HostTraits> hosts, {
    bool includeCategories = false,
  }) => FilterOptions(
    languages: _sorted([...languages, for (final h in hosts) ...h.languages]),
    topics: _sorted([
      ...topics,
      for (final h in hosts) ...[
        ...h.topics,
        if (includeCategories) ...[...h.categories, h.specialization],
      ],
    ]),
  );

  /// `LANG_HINDI` / `LANGUAGE_TAMIL_NADU` → `HINDI` / `TAMIL NADU`.
  static String cleanLanguageName(String? text) {
    var s = (text ?? '').trim();
    final upper = s.toUpperCase();
    if (upper.startsWith('LANG_')) {
      s = s.substring(5);
    } else if (upper.startsWith('LANGUAGE_')) {
      s = s.substring(9);
    }
    return s.replaceAll('_', ' ').trim();
  }

  static List<String> _sorted(Iterable<String> values) => {
    for (final v in values)
      if (v.isNotEmpty) v,
  }.toList()..sort();
}
