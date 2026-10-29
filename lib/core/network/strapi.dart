import '../config/env.dart';

/// JSON object as returned by the backend.
typedef JsonMap = Map<String, dynamic>;

/// Helpers for Strapi v4/v5 payloads (port of RN `expert.utils.js`).
abstract final class Strapi {
  /// Unwraps `{data: …}` and `{id, attributes: {…}}` nesting (RN `xnode`).
  static dynamic node(dynamic n) {
    if (n is Map) {
      if (n.containsKey('data') && n['data'] != null) return node(n['data']);
      final attrs = n['attributes'];
      if (attrs is Map) return <String, dynamic>{'id': n['id'], ...attrs};
    }
    return n;
  }

  /// [node] as a map, or null.
  static JsonMap? map(dynamic n) {
    final v = node(n);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// Normalized list (RN `xlist`): always a list, items unwrapped.
  static List<JsonMap> list(dynamic n) {
    final v = node(n);
    if (v == null) return const [];
    final items = v is List ? v : [v];
    return [for (final item in items) ?map(item)];
  }

  /// Body of a Strapi response: `response.data` → `data` → node.
  static dynamic body(dynamic responseData) {
    if (responseData is Map && responseData.containsKey('data')) {
      return node(responseData['data']);
    }
    return node(responseData);
  }

  /// `meta.pagination` from a list response.
  static JsonMap? pagination(dynamic responseData) {
    if (responseData is! Map) return null;
    final meta = responseData['meta'];
    final p = meta is Map ? meta['pagination'] : null;
    return p is Map ? Map<String, dynamic>.from(p) : null;
  }

  /// Absolute media URL (RN `media`).
  static String? mediaUrl(dynamic url) {
    if (url == null) return null;
    final s = url.toString();
    if (s.isEmpty) return null;
    // A local file (the host's own new recording, in the preview) as is.
    return s.startsWith('http') || s.startsWith('file:')
        ? s
        : '${Env.apiBaseUrl}$s';
  }

  /// Best URL for a Strapi media node, original first (RN `mediaFromAsset`).
  static String? mediaFromAsset(dynamic asset) {
    final m = map(asset) ?? const {};
    final Map formats = m['formats'] is Map ? m['formats'] as Map : const {};
    String? f(String k) => formats[k] is Map ? formats[k]['url'] : null;
    return mediaUrl(
      m['url'] ?? f('large') ?? f('medium') ?? f('small') ?? f('thumbnail'),
    );
  }

  /// Card-sized rendition (RN `mediaThumbFromAsset`): medium/small first so
  /// grids don't decode multi-MB originals.
  static String? mediaThumbFromAsset(dynamic asset) {
    final m = map(asset) ?? const {};
    final Map formats = m['formats'] is Map ? m['formats'] as Map : const {};
    String? f(String k) => formats[k] is Map ? formats[k]['url'] : null;
    return mediaUrl(
      f('medium') ?? f('small') ?? f('large') ?? m['url'] ?? f('thumbnail'),
    );
  }

  /// The `thumbnail` rendition only (~245 px, a few KB): a placeholder that
  /// lands long before the card image. Null without one — a placeholder as
  /// large as the image it stands in for buys nothing.
  static String? mediaTinyFromAsset(dynamic asset) {
    final m = map(asset) ?? const {};
    final Map formats = m['formats'] is Map ? m['formats'] as Map : const {};
    return mediaUrl(
      formats['thumbnail'] is Map ? formats['thumbnail']['url'] : null,
    );
  }
}

/// Lenient readers for loosely typed JSON (numbers as strings, etc.).
abstract final class J {
  static String? str(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static int? integer(dynamic v) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? double.tryParse(s)?.toInt(),
    _ => null,
  };

  static double? number(dynamic v) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };

  static bool boolean(dynamic v) => switch (v) {
    final bool b => b,
    final num n => n != 0,
    final String s => s == 'true' || s == '1',
    _ => false,
  };

  static DateTime? date(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}
