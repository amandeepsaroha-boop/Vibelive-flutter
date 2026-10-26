import '../../../api/authscreen/interests_models.dart';

/// Gender has no field on the public user: it is the interests answer
/// "How do you identify?" (`user_gender`), which the host onboarding reads
/// too. Values: `Female` / `Male` / `Others`.
abstract final class GenderAnswer {
  static const question = 'user_gender';
  static const values = ['Female', 'Male', 'Others'];

  /// The saved answer as a gender, or null.
  static String? fromAnswers(Map<String, List<String>> answers) {
    for (final v in answers[question] ?? const <String>[]) {
      final s = v.toLowerCase();
      if (s.contains('female') || s.contains('woman')) return 'Female';
      if (s.endsWith('_male') || s == 'male' || s.contains('_man')) {
        return 'Male';
      }
      if (s.contains('other') || s.contains('prefer_not')) return 'Others';
    }
    return null;
  }

  /// The form's option value for [gender] ("Other" is the neutral option
  /// the form offers), or null when the form has no such question.
  static String? optionFor(InterestForm form, String gender) {
    final q = form.question(question);
    if (q == null) return null;
    bool has(InterestOption o, String w) =>
        '${o.value} ${o.label}'.toLowerCase().contains(w);
    for (final o in q.options) {
      final match = switch (gender) {
        'Female' => has(o, 'female') || has(o, 'woman'),
        'Male' => !has(o, 'female') && (has(o, 'male') || has(o, ' man')),
        _ => has(o, 'other') || has(o, 'prefer'),
      };
      if (match) return o.value;
    }
    return null;
  }
}
