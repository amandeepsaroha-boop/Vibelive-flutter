import 'package:flutter/widgets.dart';

import '../../../../core/i18n/i18n.dart';

/// RN `formatTagline`: one line in the row; past 8 words is noise.
String formatTagline(String text) {
  final value = text.trim();
  if (value.isEmpty) return '';
  final words = value.split(RegExp(r'\s+'));
  return words.length > 8 ? '${words.take(8).join(' ')}…' : value;
}

/// RN `formatCallMinutes`: 1250 → "1.3K", 12500 → "13K", 640 → "640".
String formatCallMinutes(double minutes) {
  final value = minutes.isFinite && minutes > 0 ? minutes.floor() : 0;
  if (value < 1000) return '$value';
  final k = value / 1000;
  return '${k >= 10 ? k.round() : k.toStringAsFixed(1)}K';
}

/// 10.0 → "10", 12.5 → "12.5" (RN printed the plain number).
String formatRate(double rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : '$rate';

/// Case-insensitive matcher of [query] for [highlightSpans]; null = no
/// highlight.
RegExp? highlightPattern(String query) {
  final q = query.trim();
  return q.isEmpty ? null : RegExp(RegExp.escape(q), caseSensitive: false);
}

/// [text] as spans with every match of [pattern] in [highlight] (RN
/// `HighlightedText`). One span list, so ellipsis still works.
List<TextSpan> highlightSpans(
  String text,
  RegExp? pattern,
  TextStyle highlight,
) {
  if (pattern == null || text.isEmpty) return [TextSpan(text: text)];
  final spans = <TextSpan>[];
  var start = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.end == m.start) continue;
    if (m.start > start) {
      spans.add(TextSpan(text: text.substring(start, m.start)));
    }
    spans.add(TextSpan(text: m[0], style: highlight));
    start = m.end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return spans;
}

/// `context.t` with [values] inserted verbatim. i18next HTML-escapes
/// interpolated values (`&` → `&amp;`) and would parse `{{…}}` / `$t(…)`
/// typed by the user, so placeholders are swapped in after translating.
String tVerbatim(BuildContext context, String key, Map<String, String> values) {
  var i = 0;
  final markers = {
    for (final k in values.keys) k: String.fromCharCode(0xE000 + i++),
  };
  var out = context.t(key, variables: markers);
  values.forEach((k, v) => out = out.replaceAll(markers[k]!, v));
  return out;
}
