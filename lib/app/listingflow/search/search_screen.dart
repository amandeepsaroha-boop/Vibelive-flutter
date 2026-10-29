import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/filter_models.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../../homescreen/discover/active_filters.dart';
import '../filter/filter_sheet.dart';
import '../profile/host_profile_sheet.dart';
import 'helper/search_controller.dart';
import 'search_header.dart';
import 'search_results.dart';

/// Host search, `/search` (RN `searchscreen`): `GET /search` as you type
/// (debounced), language / topic filter over the hits, and a tap opens the
/// full profile. `?q=` (deep link) pre-fills and runs a query.
class SearchScreen extends HookWidget {
  const SearchScreen({super.key});

  /// `q` of the route, also when it changes while the screen is open.
  static String _linkQuery(BuildContext context) {
    if (GoRouter.maybeOf(context) == null) return '';
    return GoRouterState.of(context).uri.queryParameters['q']?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final link = _linkQuery(context);
    final search = useMemoized(
      () => SearchScreenController(initialQuery: link),
    );
    useEffect(() => search.dispose, [search]);
    useEffect(() {
      if (link.isNotEmpty && link != search.query.value) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => search.searchFor(link, trigger: 'link'),
        );
      }
      return null;
    }, [link]);

    Future<void> openFilter() async {
      final next = await showHostFilterSheet(
        context,
        current: search.filter.value,
        hosts: search.hits,
        includeCategories: true,
        source: 'search',
      );
      if (next != null && context.mounted) search.filter.value = next;
    }

    void back() {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        // Opened from a link with nothing underneath.
        context.go(AppRoutes.home);
      }
    }

    final c = context.colors;
    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SearchHeader(
                    controller: search,
                    onBack: back,
                    onOpenFilter: openFilter,
                  ),
                  ValueListenableBuilder<HostFilter>(
                    valueListenable: search.filter,
                    builder: (_, filter, _) => filter.isActive
                        ? Padding(
                            padding: EdgeInsets.fromLTRB(4.ms, 0, 4.ms, 4.ms),
                            child: ActiveFilters(
                              filter: filter,
                              source: 'search',
                              onChanged: (f) => search.filter.value = f,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: SearchResultsView(
                      controller: search,
                      onOpen: (hit) => search.open(hit, (host) async {
                        if (context.mounted) {
                          await showHostProfile(
                            context,
                            host,
                            source: 'search',
                          );
                        }
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
