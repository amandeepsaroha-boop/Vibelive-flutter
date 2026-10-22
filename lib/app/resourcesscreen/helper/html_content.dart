import 'content_blocks.dart';

/// CMS HTML → [ContentBlock]s: the subset `react-native-render-html` drew
/// on these pages (headings, paragraphs, lists, bold / italic / underline /
/// strike / code, links, line breaks). Unknown tags keep their text;
/// `<script>` / `<style>` are dropped.
abstract final class HtmlContent {
  static List<ContentBlock> parse(String html) => _HtmlReader(html).read();

  static final _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);');

  static const _named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'rsquo': '’',
    'lsquo': '‘',
    'rdquo': '”',
    'ldquo': '“',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'bull': '•',
    'middot': '·',
    'copy': '©',
    'reg': '®',
    'trade': '™',
    'times': '×',
    'deg': '°',
    'rarr': '→',
    'larr': '←',
    'laquo': '«',
    'raquo': '»',
    'rupee': '₹',
  };

  static String decode(String s) => s.replaceAllMapped(_entity, (m) {
    final body = m[1]!;
    if (body.startsWith('#')) {
      final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final code = int.tryParse(
        hex ? body.substring(2) : body.substring(1),
        radix: hex ? 16 : 10,
      );
      return code == null || code <= 0 || code > 0x10FFFF
          ? m[0]!
          : String.fromCharCode(code);
    }
    return _named[body.toLowerCase()] ?? m[0]!;
  });
}

class _ListContext {
  _ListContext({required this.ordered, this.next = 1});
  final bool ordered;
  int next;
}

class _HtmlReader {
  _HtmlReader(this.src);
  final String src;

  /// Comment | tag (1: `/`, 2: name, 3: attributes, quotes may hold `>`) |
  /// text (4) | a stray `<`.
  static final _token = RegExp(
    r'''<!--[\s\S]*?-->|<(/?)([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>|([^<]+)|<''',
  );
  static final _href = RegExp(
    r'''href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
  );
  static final _start = RegExp(
    r'''start\s*=\s*["']?(\d+)''',
    caseSensitive: false,
  );
  static const _blockTags = {
    'p',
    'div',
    'blockquote',
    'section',
    'article',
    'header',
    'footer',
    'pre',
    'table',
    'tr',
    'hr',
    'figure',
    'figcaption',
  };

  final _blocks = <ContentBlock>[];
  var _runs = <InlineRun>[];
  final _lists = <_ListContext>[];
  final _hrefs = <String?>[];
  int? _heading;
  var _inItem = 0;
  String? _marker;
  var _bold = 0, _italic = 0, _underline = 0, _strike = 0, _code = 0;
  var _skip = 0;

  List<ContentBlock> read() {
    for (final m in _token.allMatches(src)) {
      final name = m[2]?.toLowerCase();
      if (name != null) {
        _tag(name, closing: m[1] == '/', attrs: m[3] ?? '');
      } else if (m[4] != null) {
        _text(m[4]!);
      } else if (!m[0]!.startsWith('<!--')) {
        _text(m[0]!); // a stray '<'
      }
    }
    _flush();
    return _blocks;
  }

  void _tag(String name, {required bool closing, required String attrs}) {
    final delta = closing ? -1 : 1;
    switch (name) {
      case 'script' || 'style' || 'head' || 'title':
        _skip = (_skip + delta).clamp(0, 99);
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _flush();
        _heading = closing ? null : int.parse(name.substring(1));
      case 'ul' || 'ol':
        _flush();
        if (closing) {
          if (_lists.isNotEmpty) _lists.removeLast();
        } else {
          final start = int.tryParse(_start.firstMatch(attrs)?[1] ?? '');
          _lists.add(_ListContext(ordered: name == 'ol', next: start ?? 1));
        }
      case 'li':
        _flush();
        if (closing) {
          _inItem = (_inItem - 1).clamp(0, 99);
          _marker = null;
        } else {
          final list = _lists.isEmpty ? null : _lists.last;
          _inItem++;
          _marker = list != null && list.ordered ? '${list.next++}.' : '•';
        }
      case 'br':
        _runs.add(_style('\n'));
      case 'td' || 'th':
        if (closing) _runs.add(_style(' '));
      case 'strong' || 'b':
        _bold = (_bold + delta).clamp(0, 99);
      case 'em' || 'i' || 'cite':
        _italic = (_italic + delta).clamp(0, 99);
      case 'u' || 'ins':
        _underline = (_underline + delta).clamp(0, 99);
      case 's' || 'strike' || 'del':
        _strike = (_strike + delta).clamp(0, 99);
      case 'code' || 'kbd' || 'samp':
        _code = (_code + delta).clamp(0, 99);
      case 'a':
        if (closing) {
          if (_hrefs.isNotEmpty) _hrefs.removeLast();
        } else {
          final h = _href.firstMatch(attrs);
          final raw = h?[1] ?? h?[2] ?? h?[3];
          _hrefs.add(raw == null ? null : HtmlContent.decode(raw).trim());
        }
      default:
        if (_blockTags.contains(name)) _flush();
    }
  }

  void _text(String raw) {
    if (_skip > 0) return;
    final text = HtmlContent.decode(raw.replaceAll(RegExp(r'\s+'), ' '));
    if (text.isEmpty) return;
    _runs.add(_style(text));
  }

  InlineRun _style(String text) => InlineRun(
    text,
    bold: _bold > 0,
    italic: _italic > 0,
    underline: _underline > 0,
    strike: _strike > 0,
    code: _code > 0,
    href: _hrefs.isEmpty ? null : _hrefs.last,
  );

  /// Emits the pending text as a block of the current kind.
  void _flush() {
    final runs = _clean(_runs);
    _runs = <InlineRun>[];
    if (runs.isEmpty) return;
    final heading = _heading;
    if (heading != null) {
      _blocks.add(HeadingBlock(heading, runs));
    } else if (_inItem > 0) {
      _blocks.add(
        ListItemBlock(
          _marker ?? '',
          runs,
          depth: (_lists.length - 1).clamp(0, 9),
        ),
      );
      _marker = ''; // more paragraphs of this item: no second bullet
    } else {
      _blocks.add(ParagraphBlock(runs));
    }
  }

  /// Collapses the spaces HTML would not draw: around line breaks, between
  /// runs, and at both ends of the block.
  static List<InlineRun> _clean(List<InlineRun> runs) {
    final out = <InlineRun>[];
    var lastChar = '\n';
    for (final r in runs) {
      var t = r.text;
      if (lastChar == ' ' || lastChar == '\n') {
        t = t.replaceFirst(RegExp('^ +'), '');
      }
      t = t.replaceAll(RegExp(r' *\n *'), '\n');
      if (t.isEmpty) continue;
      if (t.startsWith('\n') && out.isNotEmpty) {
        final prev = out.removeLast();
        final trimmed = prev.text.replaceFirst(RegExp(r' +$'), '');
        if (trimmed.isNotEmpty) out.add(prev.withText(trimmed));
      }
      out.add(r.withText(t));
      lastChar = t[t.length - 1];
    }
    // Trailing spaces / breaks.
    while (out.isNotEmpty) {
      final last = out.removeLast();
      final trimmed = last.text.replaceFirst(RegExp(r'[ \n]+$'), '');
      if (trimmed.isNotEmpty) {
        out.add(last.withText(trimmed));
        break;
      }
    }
    // Leading breaks.
    while (out.isNotEmpty && out.first.text.startsWith('\n')) {
      final first = out.removeAt(0);
      final trimmed = first.text.replaceFirst(RegExp(r'^[ \n]+'), '');
      if (trimmed.isNotEmpty) {
        out.insert(0, first.withText(trimmed));
        break;
      }
    }
    return out;
  }
}
