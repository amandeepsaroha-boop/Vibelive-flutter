import '../../../api/authscreen/interests_models.dart';
import 'draft_models.dart';

/// The interests form's topic question ("support topics"): what the
/// Interests step lists and what `/me/service-areas` saves for it.
abstract final class HostTopicCatalog {
  static const questionKey = 'support_topic';

  /// Used when the admin sets no limit.
  static const defaultMax = 5;

  /// `support_topic`, else the first multi-select topic question.
  static InterestQuestion? question(InterestForm? form) {
    if (form == null) return null;
    final byKey = form.question(questionKey);
    if (byKey != null && !byKey.isDeprecated) return byKey;
    for (final q in form.questions) {
      if (!q.isDeprecated &&
          q.isMulti &&
          q.type == InterestQuestionType.interest) {
        return q;
      }
    }
    return null;
  }

  static List<HostTopic> topics(InterestQuestion? q) => [
    if (q != null)
      for (final o in q.options)
        if (!o.isDeprecated)
          HostTopic(
            value: o.value,
            label: o.label,
            emoji: '${o.metadata['emoji'] ?? ''}',
          ),
  ];

  static int maxSelect(InterestQuestion? q) => q?.maxSelect ?? defaultMax;

  /// Saved answers → topics, in catalog order.
  static List<HostTopic> selected(
    InterestQuestion? q,
    Map<String, List<String>> selections,
  ) {
    if (q == null) return const [];
    final values = (selections[q.key] ?? const <String>[]).toSet();
    return [
      for (final t in topics(q))
        if (values.contains(t.value)) t,
    ];
  }
}
