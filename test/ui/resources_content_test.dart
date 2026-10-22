import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/api/resourcesscreen/resources_models.dart';
import 'package:vibelive/app/resourcesscreen/helper/content_blocks.dart';
import 'package:vibelive/app/resourcesscreen/helper/html_content.dart';
import 'package:vibelive/app/resourcesscreen/helper/page_content.dart';
import 'package:vibelive/app/resourcesscreen/helper/resource_links.dart';
import 'package:vibelive/app/resourcesscreen/helper/resource_menu.dart';
import 'package:vibelive/core/router/app_router.dart';

void main() {
  group('HtmlContent', () {
    test('headings, paragraphs, marks, links and entities', () {
      final blocks = HtmlContent.parse(
        '<h2>Privacy &amp; Terms</h2>\n'
        '<p>We  <strong>never</strong> sell\n your <em>data</em>.'
        ' See <a href="https://x.com/a?b=1&amp;c=2">this</a>.</p>'
        '<script>alert(1)</script><p>&nbsp;</p><p>Fee: &#8377;10 &mdash; ok</p>',
      );
      // `<p>&nbsp;</p>` stays a blank spacer line, as in RenderHTML.
      expect(blocks, hasLength(4));
      expect(blocks[2].text, '\u00A0');
      final h = blocks[0] as HeadingBlock;
      expect(h.level, 2);
      expect(h.text, 'Privacy & Terms');
      final p = blocks[1] as ParagraphBlock;
      expect(p.text, 'We never sell your data. See this.');
      expect(p.runs.firstWhere((r) => r.text == 'never').bold, isTrue);
      expect(p.runs.firstWhere((r) => r.text == 'data').italic, isTrue);
      expect(
        p.runs.firstWhere((r) => r.text == 'this').href,
        'https://x.com/a?b=1&c=2',
      );
      expect(blocks[3].text, 'Fee: ₹10 — ok');
    });

    test('lists: bullets, numbers, nested items, li > p, <br>', () {
      final blocks = HtmlContent.parse(
        '<ul><li>One</li><li><p>Two</p><p>more</p></li></ul>'
        '<ol start="3"><li>Three<ul><li>Inner</li></ul></li><li>Four</li></ol>'
        '<p>a<br/> b</p>',
      );
      final items = blocks.whereType<ListItemBlock>().toList();
      expect(
        [for (final i in items) '${i.depth}${i.marker}${i.text}'],
        ['0•One', '0•Two', '0more', '03.Three', '1•Inner', '04.Four'],
      );
      expect(blocks.last.text, 'a\nb');
    });

    test('plain text is one paragraph (RN wraps it in <p>)', () {
      const page = MenuPage(slug: 'faq', content: 'Just  text');
      final blocks = PageContent.blocksOf(page);
      expect(blocks.single, isA<ParagraphBlock>());
      expect(blocks.single.text, 'Just text');
    });
  });

  test('Strapi blocks: heading, marks, link, ordered list', () {
    final blocks = StrapiBlocks.parse([
      {
        'type': 'heading',
        'level': 9,
        'children': [
          {'type': 'text', 'text': 'Refunds'},
        ],
      },
      {
        'type': 'paragraph',
        'children': [
          {'type': 'text', 'text': 'Mail ', 'bold': true},
          {
            'type': 'link',
            'url': 'mailto:a@b.co',
            'children': [
              {'type': 'text', 'text': 'us'},
            ],
          },
        ],
      },
      {
        'type': 'list',
        'format': 'ordered',
        'children': [
          {
            'type': 'list-item',
            'children': [
              {'type': 'text', 'text': 'First'},
            ],
          },
          {
            'type': 'list-item',
            'children': [
              {'type': 'text', 'text': 'Second', 'strikethrough': true},
            ],
          },
        ],
      },
      {
        'type': 'paragraph',
        'children': [
          {'type': 'text', 'text': '  '},
        ],
      },
    ]);
    expect(blocks, hasLength(4));
    expect((blocks[0] as HeadingBlock).level, 6);
    expect(blocks[1].runs.first.bold, isTrue);
    expect(blocks[1].runs.last.href, 'mailto:a@b.co');
    expect((blocks[2] as ListItemBlock).marker, '1.');
    expect((blocks[3] as ListItemBlock).marker, '2.');
    expect(blocks[3].runs.single.strike, isTrue);
  });

  test('menu: CMS pages go before Logout; routes encode the title', () {
    final cat = ResourceMenu.category(
      'resources',
      isExpert: false,
      pages: const [MenuPage(slug: 'refund', title: 'Refund & Returns')],
    )!;
    final ids = [for (final i in cat.items) i.id];
    expect(ids.last, 'logout');
    expect(ids[ids.length - 2], 'dynamic-refund');
    final route = cat.items[ids.length - 2].route!;
    final uri = Uri.parse(route);
    expect(uri.path, AppRoutes.dynamicPage);
    expect(uri.queryParameters, {
      'slug': 'refund',
      'title': 'Refund & Returns',
    });
    expect(ResourceMenu.category('nope', isExpert: true), isNull);
    // Identity: hosts get Share/QR, clients get Become a Host.
    final client = ResourceMenu.category('identity', isExpert: false)!;
    expect([for (final i in client.items) i.id], ['personal', 'become-host']);
  });

  test('links: scheme-less domains get https, relative links do not open', () {
    expect(
      ResourceLinks.parse('www.x.com/a').toString(),
      'https://www.x.com/a',
    );
    expect(ResourceLinks.parse('/terms'), isNull);
    expect(ResourceLinks.parse('mailto:a@b.co')!.scheme, 'mailto');
    expect(ResourceLinks.whatsapp('98765 43210'), 'https://wa.me/919876543210');
    expect(ResourceLinks.tel('+91 98765-43210'), 'tel:+919876543210');
  });
}
