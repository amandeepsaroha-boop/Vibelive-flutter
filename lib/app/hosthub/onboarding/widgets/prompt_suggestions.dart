import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/i18n/i18n.dart';
import '../helper/draft_models.dart';
import '../helper/suggestions.dart';
import 'suggestion_card.dart';

typedef HostSuggestionSource =
    List<String> Function(HostTranslate t, List<String> topics, int page);

/// Suggestions for a text step, from the chosen topics. Rebuilds on topic
/// or page changes, never while the user types.
class HostPromptSuggestions extends HookWidget {
  const HostPromptSuggestions({
    super.key,
    required this.topics,
    required this.page,
    required this.target,
    required this.source,
  });

  final ValueListenable<List<HostTopic>> topics;
  final ValueNotifier<int> page;

  /// The field "Use" fills.
  final TextEditingController target;
  final HostSuggestionSource source;

  @override
  Widget build(BuildContext context) {
    final chosen = useValueListenable(topics);
    final p = useValueListenable(page);
    final locale = Localizations.localeOf(context);
    final ideas = useMemoized(
      () => source((key, vars) => context.t(key, variables: vars), [
        for (final t in chosen) t.label,
      ], p),
      [chosen, p, locale],
    );
    return HostSuggestionCard(
      suggestions: ideas,
      onUse: (s) => target.value = TextEditingValue(
        text: s,
        selection: TextSelection.collapsed(offset: s.length),
      ),
      onAnother: () => page.value = p + 1,
    );
  }
}
