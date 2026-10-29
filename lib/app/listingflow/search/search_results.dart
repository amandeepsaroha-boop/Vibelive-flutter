import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/discover_events.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../api/listingflow/search_models.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/skeleton.dart';
import 'helper/search_controller.dart';
import 'helper/search_format.dart';
import 'search_category_row.dart';
import 'search_host_row.dart';

/// Results under the header: idle hint, skeleton on the first search,
/// error / empty states, then Experts · Categories · Categories by location.
/// Rebuilds when the debounced query, the filter or the data change, never
/// per keystroke. While a new query loads the previous results stay, with a
/// thin progress line on top.
class SearchResultsView extends HookWidget {
  const SearchResultsView({
    super.key,
    required this.controller,
    required this.onOpen,
  });

  final SearchScreenController controller;
  final ValueChanged<SearchHost> onOpen;

  @override
  Widget build(BuildContext context) {
    final q = useValueListenable(controller.query);
    final typing = useValueListenable(controller.typing);
    final filter = useValueListenable(controller.filter);
    final search = useSearch(context, q);
    final scroll = useScrollController();

    final data = q.isEmpty ? null : search.data;
    controller.hits = data?.experts ?? const [];
    final experts = useMemoized(
      () => [
        for (final e in data?.experts ?? const <SearchHost>[])
          if (filter.matches(e)) e,
      ],
      [data, filter],
    );
    final highlight = useMemoized(() => highlightPattern(q), [q]);

    // A new query starts at the top.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients && scroll.offset > 0) scroll.jumpTo(0);
      });
      return null;
    }, [q]);

    final hasResults =
        data != null &&
        (experts.isNotEmpty ||
            data.categories.isNotEmpty ||
            data.categoryLocations.isNotEmpty);
    final fetching = q.isNotEmpty && search.isFetching;
    final error = search.error;

    // Analytics: one `search` per settled query (never per keystroke), and
    // its no-results / failed outcome.
    final settled =
        q.isNotEmpty && !fetching && (data != null || error != null);
    final logged = useRef<String?>(null);
    useEffect(() {
      if (!settled || logged.value == q) return null;
      logged.value = q;
      if (data == null) {
        DiscoverEvents.searchFailed(term: q, error: Analytics.errorCode(error));
        return null;
      }
      DiscoverEvents.search(
        term: q,
        resultsCount: data.experts.length,
        categoriesCount: data.categories.length + data.categoryLocations.length,
        trigger: controller.trigger,
      );
      if (!hasResults) DiscoverEvents.searchNoResults(term: q);
      return null;
    }, [settled, q]);

    final List<Widget> body;
    if (q.isEmpty && !typing) {
      body = const [SliverToBoxAdapter(child: _Idle())];
    } else if (hasResults) {
      body = [
        if (experts.isNotEmpty) ...[
          const _SectionTitle('search:sections.experts'),
          SliverList.builder(
            itemCount: experts.length,
            itemBuilder: (_, i) => SearchHostRow(
              key: ValueKey(
                SearchScreenController.hitKey(experts[i]) ?? 'hit-$i',
              ),
              hit: experts[i],
              highlight: highlight,
              opening: controller.opening,
              onOpen: (hit) {
                DiscoverEvents.searchResultTapped(
                  hostId:
                      hit.documentId ?? hit.userDocumentId ?? hit.handler ?? '',
                  position: i,
                  resultsCount: experts.length,
                  filtered: filter.isActive,
                );
                onOpen(hit);
              },
            ),
          ),
          const _SectionGap(),
        ],
        if (data.categories.isNotEmpty) ...[
          const _SectionTitle('search:sections.categories'),
          SliverList.builder(
            itemCount: data.categories.length,
            itemBuilder: (_, i) => SearchCategoryRow.category(
              category: data.categories[i],
              onSearch: (name) {
                DiscoverEvents.searchCategoryTapped(
                  kind: 'category',
                  category: name,
                  position: i,
                );
                controller.searchFor(name);
              },
            ),
          ),
          const _SectionGap(),
        ],
        if (data.categoryLocations.isNotEmpty) ...[
          const _SectionTitle('search:sections.category_locations'),
          SliverList.builder(
            itemCount: data.categoryLocations.length,
            itemBuilder: (_, i) => SearchCategoryRow.location(
              location: data.categoryLocations[i],
              onSearch: (name) {
                DiscoverEvents.searchCategoryTapped(
                  kind: 'location',
                  category: name,
                  position: i,
                );
                controller.searchFor(name);
              },
            ),
          ),
        ],
      ];
    } else if (q.isNotEmpty &&
        data == null &&
        search.isError &&
        error != null) {
      body = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: CStateView.error(
            context,
            error,
            onRetry: () => search.refetch(),
          ),
        ),
      ];
    } else if (data != null && !fetching) {
      body = [SliverToBoxAdapter(child: _Empty(q))];
    } else {
      body = const [SliverToBoxAdapter(child: _Skeleton())];
    }

    return Stack(
      children: [
        CustomScrollView(
          controller: scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 40 + the bottom inset; SliverSafeArea reads the inset itself,
            // so keyboard frames don't rebuild this whole view.
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, 40.ms),
              sliver: SliverSafeArea(
                top: false,
                left: false,
                right: false,
                sliver: SliverMainAxisGroup(slivers: body),
              ),
            ),
          ],
        ),
        if (fetching && hasResults)
          const Positioned(top: 0, left: 0, right: 0, child: _FetchLine()),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.titleKey);
  final String titleKey;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.only(bottom: 10.ms),
      child: CText(
        titleKey,
        size: 11,
        weight: FontWeight.w900,
        letterSpacing: 2,
        uppercase: true,
        color: context.colors.text.withValues(alpha: 0.55),
      ),
    ),
  );
}

/// RN section `marginBottom: 18` (rows already leave 10).
class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) =>
      SliverToBoxAdapter(child: SizedBox(height: 8.ms));
}

/// Empty field: what can be searched.
class _Idle extends StatelessWidget {
  const _Idle();

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    return Padding(
      padding: EdgeInsets.only(top: 60.ms),
      child: Column(
        children: [
          Icon(
            LucideIcons.search,
            size: 34.ms,
            color: dark ? AppColors.whiteA(0.2) : AppColors.blackA(0.15),
          ),
          SizedBox(height: 12.ms),
          CText(
            'search:idle',
            size: 13,
            weight: FontWeight.w600,
            align: TextAlign.center,
            color: dark ? AppColors.whiteA(0.4) : AppColors.blackA(0.35),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.query);
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 30.ms),
      child: CStateView(
        title: 'search:empty.title',
        message: tVerbatim(context, 'search:empty.message', {'query': query}),
        translateMessage: false,
        icon: LucideIcons.searchX,
      ),
    );
  }
}

/// First search: rows shaped like the hits.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 12.ms),
            child: SkeletonBox(width: 70.ms, height: 10.ms, radius: 5),
          ),
          for (var i = 0; i < 5; i++) const SearchHostRowSkeleton(),
        ],
      ),
    );
  }
}

/// Thin indeterminate line while a new query loads over kept results.
class _FetchLine extends StatelessWidget {
  const _FetchLine();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: SizedBox(
        height: 2,
        child: LinearProgressIndicator(
          color: c.accent,
          backgroundColor: AppColors.transparent,
        ),
      ),
    );
  }
}
