import '../../../core/config/env.dart';
import '../../../core/network/strapi.dart';

typedef ExpertiseAnswers = Map<String, List<String>>;

/// `/me/service-areas`: the host's answers to the interests-form questions
/// (RN `normalizeInterestSelectionsResponse`).
class ExpertiseSelections {
  const ExpertiseSelections({
    required this.appKey,
    this.appName = '',
    this.selections = const {},
  });

  factory ExpertiseSelections.fromResponse(dynamic body) {
    final m = body is Map ? body : const {};
    final app = m['app'] is Map ? m['app'] as Map : const {};
    return ExpertiseSelections(
      appKey: _trim(app['key']).isEmpty ? Env.appPlatform : _trim(app['key']),
      appName: _trim(app['name']),
      selections: normalize(m['selections']),
    );
  }

  final String appKey;
  final String appName;

  /// Question key → selected option values (trimmed, unique).
  final ExpertiseAnswers selections;

  /// RN `hasExpertiseSelections`: any question has an answer.
  bool get hasAny => selections.values.any((v) => v.isNotEmpty);

  /// Labels of the selected expertise options; needs the interests form.
  List<String> titlesFor(Iterable<JsonMap> questions) =>
      ExpertiseQuestions.titles(questions, selections);

  /// RN `normalizeSelections`: non-empty keys, trimmed unique values.
  static ExpertiseAnswers normalize(dynamic raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (_trim(e.key).isNotEmpty) _trim(e.key): _values(e.value),
    };
  }

  static List<String> _values(dynamic v) => v is List
      ? {for (final x in v) _trim(x)}.where((s) => s.isNotEmpty).toList()
      : const [];
}

/// `PUT /me/service-areas` answer.
class ExpertiseSaveResult {
  const ExpertiseSaveResult({
    required this.appKey,
    required this.savedCount,
    required this.selections,
    this.serverMessage,
  });

  factory ExpertiseSaveResult.fromResponse(dynamic body) {
    final m = body is Map ? body : const {};
    return ExpertiseSaveResult(
      appKey: J.str(m['appKey']) ?? Env.appPlatform,
      savedCount: J.integer(m['savedCount']) ?? 0,
      selections: ExpertiseSelections.normalize(m['selections']),
      serverMessage: J.str(m['message']),
    );
  }

  final String appKey;
  final int savedCount;
  final ExpertiseAnswers selections;

  /// Backend text, when sent; otherwise show `hosthub:expertise.saved`.
  final String? serverMessage;
}

/// Rules for the interests-form questions on the host Expertise screen. The
/// form comes from `/interests/form` (authscreen); these read the question
/// JSON leniently, raw or normalized.
abstract final class ExpertiseQuestions {
  /// Not asked of hosts here: `user_gender` is their own gender (already in
  /// Professional Details) and `interaction_mode` (voice/video) is not asked
  /// of hosts. They still need an answer: the server checks `required`.
  static const hiddenForHosts = {'user_gender', 'interaction_mode'};

  static String keyOf(JsonMap q) => _trim(q['key']);

  static bool isHiddenForHosts(JsonMap q) => hiddenForHosts.contains(keyOf(q));

  static bool isMulti(JsonMap q) =>
      _trim(q['selectionMode']).toLowerCase() == 'multi';

  static bool isRequired(JsonMap q) => q['required'] == true;

  /// Questions shown to hosts.
  static List<JsonMap> visibleForHosts(Iterable<JsonMap> questions) => [
    for (final q in questions)
      if (!isHiddenForHosts(q)) q,
  ];

  static List<JsonMap> _options(JsonMap q) => [
    if (q['options'] is List)
      for (final o in q['options'] as List)
        if (o is Map && _trim(o['value']).isNotEmpty)
          Map<String, dynamic>.from(o),
  ];

  static bool _isExpertise(JsonMap q) {
    final text =
        '${keyOf(q).toLowerCase()} ${_trim(q['title']).toLowerCase()} '
        '${_trim(q['helpText']).toLowerCase()}';
    return const [
      'service area',
      'service-area',
      'expertise',
      'skill',
      'category',
    ].any(text.contains);
  }

  /// RN `getSelectedExpertiseTitles`: labels of the selected options of the
  /// expertise questions (every question when none looks like expertise),
  /// deduped case-insensitively.
  static List<String> titles(
    Iterable<JsonMap> questions,
    ExpertiseAnswers selections,
  ) {
    final all = questions.toList();
    final expertise = all.where(_isExpertise).toList();
    final target = expertise.isNotEmpty ? expertise : all;
    final seen = <String>{};
    final titles = <String>[];
    for (final q in target) {
      final key = keyOf(q);
      if (key.isEmpty) continue;
      final labels = {
        for (final o in _options(q))
          _trim(o['value']): _trim(o['label']).isEmpty
              ? _trim(o['value'])
              : _trim(o['label']),
      };
      for (final value in selections[key] ?? const <String>[]) {
        final title = (labels[value.trim()] ?? value).trim();
        if (title.isNotEmpty && seen.add(title.toLowerCase())) {
          titles.add(title);
        }
      }
    }
    return titles;
  }

  /// RN `buildDraftSelections`: saved answers first. A question with no
  /// saved answer stays empty once the host has saved anything, except a
  /// hidden one, which always falls back to the admin default (otherwise a
  /// required hidden question would block the save invisibly).
  static ExpertiseAnswers draft(
    Iterable<JsonMap> questions,
    ExpertiseAnswers saved,
  ) {
    final hasSaved = saved.isNotEmpty;
    final out = <String, List<String>>{};
    for (final q in questions) {
      final key = keyOf(q);
      if (key.isEmpty) continue;
      final current = ExpertiseSelections._values(saved[key]);
      if (current.isNotEmpty) {
        out[key] = current;
      } else if (hasSaved && !isHiddenForHosts(q)) {
        out[key] = [];
      } else {
        final defaults = [
          for (final o in _options(q))
            if (o['isDefault'] == true) _trim(o['value']),
        ];
        out[key] = isMulti(q) ? defaults : defaults.take(1).toList();
      }
    }
    return out;
  }

  /// RN `validateSelections`: question key → i18n error key. Hidden
  /// questions are skipped (nothing on screen could show the error).
  static Map<String, String> validate(
    Iterable<JsonMap> questions,
    ExpertiseAnswers selections,
  ) {
    final errors = <String, String>{};
    for (final q in questions) {
      final key = keyOf(q);
      if (key.isEmpty || isHiddenForHosts(q)) continue;
      final options = {for (final o in _options(q)) _trim(o['value'])};
      final selected = ExpertiseSelections._values(selections[key]);
      if (selected.any((v) => !options.contains(v))) {
        errors[key] = 'hosthub:expertise.errors.unknown_option';
      } else if (!isMulti(q) && selected.length > 1) {
        errors[key] = 'hosthub:expertise.errors.single_only';
      } else if (isRequired(q) && selected.isEmpty) {
        errors[key] = 'hosthub:expertise.errors.required';
      }
    }
    return errors;
  }
}

String _trim(dynamic v) => (v == null ? '' : v.toString()).trim();
