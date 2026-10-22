import '../../api/resourcesscreen/resources_models.dart';
import 'content_blocks.dart';
import 'html_content.dart';

/// What DynamicPageScreen shows for a page (RN render order: blocks, then
/// HTML, then the support fallback, then "No content available.").
abstract final class PageContent {
  static const supportSlug = 'support';
  static const aboutSlug = 'about-app';

  static List<ContentBlock> blocksOf(MenuPage page) {
    final blocks = page.blocks;
    if (blocks != null) return StrapiBlocks.parse(blocks);
    final html = page.html;
    return html == null ? const [] : HtmlContent.parse(html);
  }

  /// RN: only a missing `support` page falls back to app-config contacts.
  static bool showsSupportFallback(String slug, MenuPage page) =>
      slug == supportSlug && !page.exists;
}
