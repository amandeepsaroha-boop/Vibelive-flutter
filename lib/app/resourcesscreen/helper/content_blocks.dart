import '../../../core/network/strapi.dart';

/// A styled piece of text inside a block (RN `getTextStyleFromMarks`).
class InlineRun {
  const InlineRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;

  /// Set for links; tapping opens it.
  final String? href;

  InlineRun withText(String value) => InlineRun(
    value,
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    code: code,
    href: href,
  );
}

/// One rendered block of a CMS page. HTML and Strapi rich-text blocks both
/// become these, so one widget draws either.
sealed class ContentBlock {
  const ContentBlock(this.runs);
  final List<InlineRun> runs;

  String get text => runs.map((r) => r.text).join();
}

final class HeadingBlock extends ContentBlock {
  const HeadingBlock(this.level, super.runs);

  /// 1–6.
  final int level;
}

final class ParagraphBlock extends ContentBlock {
  const ParagraphBlock(super.runs);
}

/// A list row. [marker] is `•`, `3.`, or '' for a second paragraph of the
/// same item; [depth] is the nesting level (0 = top).
final class ListItemBlock extends ContentBlock {
  const ListItemBlock(this.marker, super.runs, {this.depth = 0});
  final String marker;
  final int depth;
}

/// Strapi blocks-editor JSON → [ContentBlock]s (RN `renderBlocks`).
abstract final class StrapiBlocks {
  static List<ContentBlock> parse(List<JsonMap> nodes) {
    final out = <ContentBlock>[];
    for (final node in nodes) {
      final children = _children(node);
      switch (node['type']) {
        case 'heading':
          final level = J.integer(node['level']) ?? 2;
          out.add(HeadingBlock(level.clamp(1, 6), _inline(children)));
        case 'list':
          _list(node, 0, out);
        case 'list-item':
          out.add(ListItemBlock('•', _inline(children)));
        default:
          // paragraph, quote, code, image…: their text as a paragraph.
          out.add(ParagraphBlock(_inline(children)));
      }
    }
    return [
      for (final b in out)
        if (b.text.trim().isNotEmpty) b,
    ];
  }

  static void _list(JsonMap node, int depth, List<ContentBlock> out) {
    final format = node['format'];
    final ordered = format == 'ordered' || format == 'numbered';
    var index = 0;
    for (final li in _children(node)) {
      if (li['type'] == 'list') {
        _list(li, depth + 1, out);
        continue;
      }
      index++;
      final inline = <JsonMap>[];
      final nested = <JsonMap>[];
      for (final c in _children(li)) {
        (c['type'] == 'list' ? nested : inline).add(c);
      }
      out.add(
        ListItemBlock(ordered ? '$index.' : '•', _inline(inline), depth: depth),
      );
      for (final n in nested) {
        _list(n, depth + 1, out);
      }
    }
  }

  static List<JsonMap> _children(Object? node) {
    final c = node is Map ? node['children'] : null;
    if (c is! List) return const [];
    return [
      for (final n in c)
        if (n is Map) Map<String, dynamic>.from(n),
    ];
  }

  static List<InlineRun> _inline(List<JsonMap> nodes, [String? href]) {
    final runs = <InlineRun>[];
    for (final n in nodes) {
      final type = n['type'];
      final isLink = type == 'link' || n['url'] != null;
      if (isLink) {
        final attrs = n['attributes'];
        final url =
            J.str(n['url']) ??
            J.str(n['href']) ??
            (attrs is Map ? J.str(attrs['href']) : null);
        final kids = _children(n);
        if (kids.isNotEmpty) {
          runs.addAll(_inline(kids, url));
        } else {
          final label = J.str(n['text']) ?? url ?? '';
          runs.add(_marked(n, label, url));
        }
        continue;
      }
      if (type == 'text' || (n['text'] != null && type == null)) {
        runs.add(_marked(n, '${n['text'] ?? ''}', href));
        continue;
      }
      final kids = _children(n);
      if (kids.isNotEmpty) runs.addAll(_inline(kids, href));
    }
    return runs;
  }

  static InlineRun _marked(JsonMap n, String text, String? href) => InlineRun(
    text,
    bold: n['bold'] == true,
    italic: n['italic'] == true,
    underline: n['underline'] == true,
    strike: n['strikethrough'] == true,
    code: n['code'] == true,
    href: href,
  );
}
