import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/analytics/events/me_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/resourcesscreen/resources_models.dart';
import '../../api/resourcesscreen/resources_queries.dart';
import '../../api/splashscreen/splash_queries.dart';
import '../../component/c_state_view.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../helper/page_content.dart';
import '../widgets/page_body.dart';
import '../widgets/page_header.dart';
import '../widgets/rich_content.dart';

/// A CMS page by slug (RN `DynamicPageScreen`): `/me/dynamic-page?slug=…&
/// title=…`, and About / Support with their fixed slugs.
class DynamicPageScreen extends HookWidget {
  const DynamicPageScreen({
    super.key,
    this.slug,
    this.title,
    this.fallbackSlug = '',
    this.fallbackTitle = 'resources:page.untitled',
  });

  /// `/me/about-app`.
  const DynamicPageScreen.about({super.key})
    : slug = null,
      title = null,
      fallbackSlug = PageContent.aboutSlug,
      fallbackTitle = 'resources:about.title';

  /// `/me/support`.
  const DynamicPageScreen.support({super.key})
    : slug = null,
      title = null,
      fallbackSlug = PageContent.supportSlug,
      fallbackTitle = 'resources:support.title';

  /// Route params; empty falls back to [fallbackSlug] / [fallbackTitle].
  final String? slug;
  final String? title;
  final String fallbackSlug;

  /// i18n key.
  final String fallbackTitle;

  @override
  Widget build(BuildContext context) {
    final param = slug?.trim() ?? '';
    final pageSlug = param.isNotEmpty ? param : fallbackSlug.trim();
    final page = useDynamicPage(context, pageSlug);
    // Read only for the support fallback; cached since the splash.
    final config = useAppConfig(context);
    final data = page.data;
    final blocks = useMemoized(
      () => data == null ? null : PageContent.blocksOf(data),
      [data],
    );

    final serverTitle = data?.title ?? '';
    final hint = title?.trim() ?? '';
    final shownTitle = serverTitle.isNotEmpty
        ? serverTitle
        : (hint.isNotEmpty ? hint : fallbackTitle);
    final translateTitle = serverTitle.isEmpty && hint.isEmpty;

    // What the page ended up showing, for analytics (once per outcome).
    final String outcome;
    final Widget content;
    if (pageSlug.isEmpty) {
      outcome = 'missing_slug';
      content = CStateView.error(
        context,
        const ApiException(
          ApiErrorType.rejected,
          messageKey: 'resources:errors.missing_page',
        ),
      );
    } else if (data == null && page.isError && page.error != null) {
      outcome = 'failed';
      content = CStateView.error(
        context,
        page.error!,
        onRetry: () => page.refetch(),
      );
    } else if (data == null || blocks == null) {
      outcome = 'loading';
      content = const PageSkeleton();
    } else if (blocks.isNotEmpty) {
      outcome = 'content';
      content = RichContent(blocks: blocks);
    } else if (PageContent.showsSupportFallback(pageSlug, data) &&
        config.data != null) {
      outcome = 'support_fallback';
      content = SupportContacts(
        contact: SupportContact.fromAppConfig(config.data!),
      );
    } else {
      outcome = 'empty';
      content = const PageEmpty();
    }
    final failure = page.error;
    useEffect(() {
      switch (outcome) {
        case 'failed' || 'missing_slug':
          ResourceEvents.pageLoadFailed(
            slug: pageSlug,
            error:
                failure ??
                const ApiException(
                  ApiErrorType.rejected,
                  messageKey: 'resources:errors.missing_page',
                ),
          );
        case 'empty':
          ResourceEvents.pageEmpty(pageSlug);
        case 'support_fallback':
          ResourceEvents.supportFallbackShown();
      }
      return null;
    }, [outcome]);

    final bottom = MediaQuery.paddingOf(context).bottom;
    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: PageHeader(
                    title: shownTitle,
                    translate: translateTitle,
                    refreshing: page.isFetching,
                    onRefresh: () {
                      ResourceEvents.pageRefreshed(pageSlug);
                      page.refetch();
                    },
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      20.ms,
                      16.ms,
                      20.ms,
                      40.ms + bottom,
                    ),
                    child: PageCard(child: content),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
