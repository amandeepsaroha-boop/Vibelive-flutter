import 'validation.dart';

/// Looks up an i18n template (`context.t` in the app, a map in tests).
typedef HostTranslate =
    String Function(String key, Map<String, dynamic> variables);

/// "Based on your interests": tagline and bio ideas built locally from the
/// chosen topics and the i18n templates (no backend, no AI). Pages are
/// deterministic: "Try another suggestion" moves to the next page.
abstract final class HostSuggestions {
  static const _taglineTopical = ['t1', 't2', 't3', 't4', 't5'];
  static const _taglineGeneric = ['g1', 'g2', 'g3', 'g4'];
  static const _bioTopical = ['t1', 't5', 't2', 't3', 't4'];
  static const _bioGeneric = ['g1', 'g2', 'g3', 'g4'];

  /// Templates that need 2 or 3 topics.
  static const _needs = {'t2': 2, 't3': 2};
  static const _bioNeeds = {'t1': 2, 't2': 2, 't4': 3};

  /// Three taglines (two from the topics, one general), each within the
  /// 60-character limit.
  static List<String> taglines(
    HostTranslate t,
    List<String> topics,
    int page,
  ) => _page(
    topical: _render(
      t,
      'hostflow:suggest.tagline',
      _taglineTopical,
      _needs,
      topics,
      HostValidation.taglineMax,
    ),
    generic: _generic(
      t,
      'hostflow:suggest.tagline',
      _taglineGeneric,
      HostValidation.taglineMax,
    ),
    page: page,
    topicalPerPage: 2,
    count: 3,
  );

  /// Two bios: one from the topics, one general.
  static List<String> bios(HostTranslate t, List<String> topics, int page) =>
      _page(
        topical: _render(
          t,
          'hostflow:suggest.bio',
          _bioTopical,
          _bioNeeds,
          topics,
          HostValidation.bioMax,
        ),
        generic: _generic(
          t,
          'hostflow:suggest.bio',
          _bioGeneric,
          HostValidation.bioMax,
        ),
        page: page,
        topicalPerPage: 1,
        count: 2,
      );

  /// "Self-love & confidence" → "self-love & confidence" (keeps acronyms).
  static String topicWord(String label) {
    final s = label.trim();
    if (s.length < 2) return s.toLowerCase();
    final second = s[1];
    if (second.toUpperCase() == second && second.toLowerCase() != second) {
      return s;
    }
    return s[0].toLowerCase() + s.substring(1);
  }

  static List<String> _render(
    HostTranslate t,
    String ns,
    List<String> keys,
    Map<String, int> needs,
    List<String> topics,
    int maxLength,
  ) {
    final words = [for (final l in topics) topicWord(l)]
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return const [];
    final out = <String>[];
    final seen = <String>{};
    // Rotate the starting topic so every topic gets a turn.
    for (var r = 0; r < words.length; r++) {
      for (final key in keys) {
        final need = needs[key] ?? 1;
        if (words.length < need) continue;
        final text = t('$ns.$key', {
          'a': words[r % words.length],
          'b': words[(r + 1) % words.length],
          'c': words[(r + 2) % words.length],
        }).trim();
        if (text.isEmpty || text.length > maxLength) continue;
        if (seen.add(text.toLowerCase())) out.add(text);
      }
    }
    return out;
  }

  static List<String> _generic(
    HostTranslate t,
    String ns,
    List<String> keys,
    int maxLength,
  ) => [
    for (final key in keys)
      if (t('$ns.$key', const {}).trim() case final s
          when s.isNotEmpty && s.length <= maxLength)
        s,
  ];

  static List<String> _page({
    required List<String> topical,
    required List<String> generic,
    required int page,
    required int topicalPerPage,
    required int count,
  }) {
    final out = <String>[];
    void add(String s) {
      if (!out.contains(s) && out.length < count) out.add(s);
    }

    final p = page < 0 ? 0 : page;
    if (topical.isNotEmpty) {
      for (var i = 0; i < topicalPerPage; i++) {
        add(topical[(p * topicalPerPage + i) % topical.length]);
      }
    }
    for (var i = 0; out.length < count && i < generic.length; i++) {
      add(generic[(p + i) % generic.length]);
    }
    for (var i = 0; out.length < count && i < topical.length; i++) {
      add(topical[(p * topicalPerPage + topicalPerPage + i) % topical.length]);
    }
    return out;
  }
}
