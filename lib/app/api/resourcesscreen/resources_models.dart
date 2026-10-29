import '../../../core/network/strapi.dart';
import '../splashscreen/splash_models.dart';

/// A CMS page from `/page-contents` (menu entry, About, Support…).
class MenuPage {
  const MenuPage({
    required this.slug,
    this.id,
    this.title = '',
    this.content,
    this.exists = true,
  });

  /// No live page has this slug (RN returned null).
  const MenuPage.missing(this.slug)
    : id = null,
      title = '',
      content = null,
      exists = false;

  factory MenuPage.fromRow(JsonMap row) => MenuPage(
    id: J.str(row['documentId']) ?? J.str(row['id']),
    slug: (J.str(row['slug']) ?? '').trim(),
    title: (J.str(row['title']) ?? J.str(row['name']) ?? '').trim(),
    content: row['content'] ?? row['Content'] ?? row['body'] ?? row['html'],
  );

  factory MenuPage.fromJson(Object? json) {
    final map = json! as Map;
    return MenuPage(
      id: J.str(map['id']),
      slug: map['slug'] as String,
      title: (map['title'] as String?) ?? '',
      content: map['content'],
      exists: map['exists'] != false,
    );
  }

  final String? id;
  final String slug;

  /// '' ⇒ use the route's title, else `resources:page.untitled`.
  final String title;

  /// HTML / plain string, or Strapi rich-text blocks (a list).
  final Object? content;
  final bool exists;

  Map<String, dynamic> toJson() => {
    'id': id,
    'slug': slug,
    'title': title,
    'content': content,
    'exists': exists,
  };

  /// Strapi blocks, when the page uses the blocks editor.
  List<JsonMap>? get blocks {
    final c = content;
    if (c is! List) return null;
    return [
      for (final b in c)
        if (b is Map) Map<String, dynamic>.from(b),
    ];
  }

  /// HTML for string content; plain text is wrapped in `<p>` (RN rule).
  String? get html {
    final c = content;
    if (c is! String || c.trim().isEmpty) return null;
    return _looksLikeHtml.hasMatch(c) ? c : '<p>$c</p>';
  }

  bool get hasContent => (blocks?.isNotEmpty ?? false) || html != null;

  /// Content as plain text (RN `contentToText`): blocks become paragraphs,
  /// HTML tags are stripped.
  String get plainText {
    final c = content;
    if (c is List) {
      return c
          .map((b) => _blockText(b).trim())
          .where((line) => line.isNotEmpty)
          .join('\n\n');
    }
    if (c is String) {
      return c
          .replaceAll(RegExp('<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    return '';
  }

  static final _looksLikeHtml = RegExp(
    r'<\/?[a-z][\s\S]*>',
    caseSensitive: false,
  );

  static String _blockText(Object? node) {
    if (node is String) return node;
    if (node is! Map) return '';
    if (node['text'] != null) return '${node['text']}';
    final children = node['children'];
    if (children is List) return children.map(_blockText).join(' ');
    return '';
  }
}

/// Support contacts from `/app-config`, shown when the `support` page is
/// missing. Read from `useAppConfig` (api/splashscreen); no extra request.
class SupportContact {
  const SupportContact({this.email, this.phone, this.whatsapp});

  factory SupportContact.fromAppConfig(AppConfig config) {
    final r = config.raw;
    return SupportContact(
      email:
          J.str(r['support_email']) ??
          J.str(r['supportEmail']) ??
          J.str(r['contact_email']),
      phone:
          J.str(r['support_phone']) ??
          J.str(r['supportPhone']) ??
          J.str(r['contact_phone']),
      whatsapp:
          J.str(r['support_whatsapp']) ??
          J.str(r['supportWhatsapp']) ??
          J.str(r['whatsapp_number']),
    );
  }

  final String? email;
  final String? phone;
  final String? whatsapp;

  /// Where support mail goes while app-config has no `supportEmail`.
  static const defaultEmail = 'developer@vocso.com';

  /// [email], else [defaultEmail]: there is always somewhere to write.
  String get emailOrDefault {
    final e = email?.trim() ?? '';
    return e.isEmpty ? defaultEmail : e;
  }

  bool get isEmpty => email == null && phone == null && whatsapp == null;
}
