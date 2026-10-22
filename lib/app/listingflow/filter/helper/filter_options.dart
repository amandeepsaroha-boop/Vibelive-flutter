import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/query/query_hooks.dart';
import '../../../api/authscreen/interests_models.dart';
import '../../../api/authscreen/interests_queries.dart';
import '../../../api/homescreen/home_keys.dart';
import '../../../api/homescreen/home_models.dart';
import '../../../api/homescreen/home_queries.dart';
import '../../../api/hosthub/catalog_models.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/listingflow/filter_models.dart';
import '../../../api/listingflow/listing_models.dart';

/// What the filter sheet offers, and whether its sources are still loading.
@immutable
class FilterSheetOptions {
  const FilterSheetOptions({
    required this.options,
    required this.languagesLoading,
    required this.topicsLoading,
    required this.languagesError,
    required this.retryLanguages,
  });

  final FilterOptions options;
  final bool languagesLoading;
  final bool topicsLoading;

  /// The `/languages` read failed and nothing else offers a language.
  final ApiException? languagesError;
  final VoidCallback retryLanguages;
}

/// RN `fetchFilterOptions` (`/languages` + the support-topic question) plus
/// the languages and topics [hosts] carry; search also offers their
/// categories ([includeCategories]). The [current] selection is always
/// offered, so it can be unticked even when no loaded host has it.
FilterSheetOptions useFilterSheetOptions(
  BuildContext context, {
  required List<HostTraits> hosts,
  required bool includeCategories,
  required HostFilter current,
}) {
  final languages = useHostLanguages(context);
  final form = useInterestForm(context);
  final langData = languages.data;
  final formData = form.data;

  final options = useMemoized(() {
    final base = FilterOptions.fromSources(
      languages: [for (final l in langData ?? const <HostOption>[]) l.label],
      topics: supportTopicsOf(formData),
    ).withHosts(hosts, includeCategories: includeCategories);
    return FilterOptions(
      languages: _union(base.languages, current.languages),
      topics: _union(base.topics, [?current.topic]),
    );
  }, [langData, formData, hosts, current]);

  final noLanguages = options.languages.isEmpty;
  return FilterSheetOptions(
    options: options,
    languagesLoading: noLanguages && langData == null && !languages.isError,
    topicsLoading: options.topics.isEmpty && formData == null && !form.isError,
    languagesError: noLanguages && languages.isError ? languages.error : null,
    retryLanguages: () => languages.refetch(),
  );
}

/// Options of the support-topic question, as Discover's topic strip reads
/// them (deprecated ones dropped).
List<SupportTopic> supportTopicsOf(InterestForm? form) => [
  for (final o
      in form?.question(SupportTopicKey.question)?.options ??
          const <InterestOption>[])
    if (!o.isDeprecated && o.value.isNotEmpty)
      SupportTopic(label: o.label.isEmpty ? o.value : o.label, value: o.value),
];

/// Every host the Discover feed has loaded so far (no request).
List<HostCard> cachedFeedHosts() {
  final feed = queryCache.getQueryData<FeedData, ApiException>(HomeKeys.feed);
  return HostPage.merge(feed?.pages ?? const <HostPage>[]);
}

List<String> _union(List<String> sorted, List<String> extra) {
  final missing = [
    for (final e in extra)
      if (e.trim().isNotEmpty && !sorted.any((s) => sameText(s, e))) e,
  ];
  if (missing.isEmpty) return sorted;
  return [...sorted, ...missing]..sort();
}
