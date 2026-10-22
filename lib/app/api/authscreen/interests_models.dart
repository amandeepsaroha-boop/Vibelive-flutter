import 'dart:io' show Platform;

import '../../../core/config/env.dart';
import '../../../core/network/strapi.dart';

/// Answers per question key, e.g. `{'expert_language': ['en', 'hi']}`.
typedef InterestSelections = Map<String, List<String>>;

/// Trimmed keys and values, empties dropped, duplicates removed in order
/// (RN `normalizeSelections`).
InterestSelections normalizeInterestSelections(Object? raw) {
  if (raw is! Map) return {};
  final out = <String, List<String>>{};
  raw.forEach((key, values) {
    final k = _trimmed(key);
    if (k.isEmpty) return;
    out[k] = values is List
        ? <String>{
            for (final v in values)
              if (_trimmed(v).isNotEmpty) _trimmed(v),
          }.toList()
        : <String>[];
  });
  return out;
}

String _trimmed(Object? v) => v?.toString().trim() ?? '';

Map _asMap(Object? v) => v is Map ? v : const {};

/// `/interests/form` answers `{app, questions}`; tolerate a `data` envelope.
Map _payload(Object? body, String field) {
  final m = _asMap(body);
  return m[field] == null && m['data'] is Map ? m['data'] as Map : m;
}

class InterestOption {
  const InterestOption({
    required this.value,
    required this.label,
    this.metadata = const {},
    this.isDeprecated = false,
    this.isDefault = false,
  });

  factory InterestOption.fromJson(Object? json) {
    final m = _asMap(json);
    final value = _trimmed(m['value']);
    final label = _trimmed(m['label']);
    return InterestOption(
      value: value,
      label: label.isEmpty ? value : label,
      metadata: m['metadata'] is Map
          ? Map<String, dynamic>.from(m['metadata'] as Map)
          : const {},
      isDeprecated: m['isDeprecated'] == true,
      isDefault: m['isDefault'] == true,
    );
  }

  final String value;
  final String label;
  final JsonMap metadata;
  final bool isDeprecated;

  /// Admin's default (pre-selected, and the neutral answer when not asked).
  final bool isDefault;

  JsonMap toJson() => {
    'value': value,
    'label': label,
    'metadata': metadata,
    'isDeprecated': isDeprecated,
    'isDefault': isDefault,
  };
}

/// Which control renders a question.
enum InterestQuestionType { gender, mode, language, interest, generic }

class InterestQuestion {
  const InterestQuestion({
    required this.key,
    this.title = '',
    this.helpText = '',
    this.selectionMode = 'single',
    this.required = false,
    this.minSelect = 0,
    this.maxSelect,
    this.isDeprecated = false,
    this.options = const [],
  });

  factory InterestQuestion.fromJson(Object? json) {
    final m = _asMap(json);
    final max = J.integer(m['maxSelect']);
    return InterestQuestion(
      key: _trimmed(m['key']),
      title: _trimmed(m['title']),
      helpText: _trimmed(m['helpText']),
      selectionMode: _trimmed(m['selectionMode']).toLowerCase() == 'multi'
          ? 'multi'
          : 'single',
      required: m['required'] == true,
      minSelect: J.integer(m['minSelect']) ?? 0,
      maxSelect: max != null && max > 0 ? max : null,
      isDeprecated: m['isDeprecated'] == true,
      options: [
        if (m['options'] is List)
          for (final o in m['options'] as List) InterestOption.fromJson(o),
      ].where((o) => o.value.isNotEmpty).toList(),
    );
  }

  final String key;
  final String title;
  final String helpText;

  /// `single` or `multi`.
  final String selectionMode;
  final bool required;
  final int minSelect;

  /// Null = no limit (the backend sends 0 or nothing for that).
  final int? maxSelect;
  final bool isDeprecated;
  final List<InterestOption> options;

  bool get isMulti => selectionMode == 'multi';

  /// RN `getQuestionType`: substring match over key, title and help text,
  /// narrowest signal first.
  InterestQuestionType get type {
    final text = '$key $title $helpText'.toLowerCase();
    bool any(List<String> words) => words.any(text.contains);
    if (text.contains('gender')) return InterestQuestionType.gender;
    if (any(const ['interaction', 'connect', 'mode', 'audio', 'video'])) {
      return InterestQuestionType.mode;
    }
    if (text.contains('language')) return InterestQuestionType.language;
    if (any(const ['interest', 'category', 'topic'])) {
      return InterestQuestionType.interest;
    }
    return InterestQuestionType.generic;
  }

  /// Gender questions are concealed on iOS. UI-only: the server still marks
  /// them required, so a hidden required question needs [neutralAnswer].
  bool get isHidden => type == InterestQuestionType.gender && Platform.isIOS;

  /// Answer for a question the user was not asked (RN `neutralAnswerFor`):
  /// the admin's default, else an explicit opt-out ("No preference"), else
  /// nothing. Never the first option: inventing a meaningful answer is worse
  /// than sending none.
  List<String> get neutralAnswer {
    for (final o in options) {
      if (o.isDefault) return [o.value];
    }
    for (final o in options) {
      if (_optOut.hasMatch(o.value.toLowerCase())) return [o.value];
    }
    return const [];
  }

  static final _optOut = RegExp(
    r'(^|_)(any|no_preference|prefer_not_say|no_pref)($|_)',
  );

  InterestQuestion copyWith({List<InterestOption>? options}) =>
      InterestQuestion(
        key: key,
        title: title,
        helpText: helpText,
        selectionMode: selectionMode,
        required: required,
        minSelect: minSelect,
        maxSelect: maxSelect,
        isDeprecated: isDeprecated,
        options: options ?? this.options,
      );

  JsonMap toJson() => {
    'key': key,
    'title': title,
    'helpText': helpText,
    'selectionMode': selectionMode,
    'required': required,
    'minSelect': minSelect,
    'maxSelect': maxSelect,
    'isDeprecated': isDeprecated,
    'options': [for (final o in options) o.toJson()],
  };
}

class InterestApp {
  const InterestApp({this.id, this.name = '', required this.key});

  factory InterestApp.fromJson(Object? json) {
    final m = _asMap(json);
    final key = _trimmed(m['key']);
    return InterestApp(
      id: m['id'],
      name: _trimmed(m['name']),
      key: key.isEmpty ? Env.appPlatform : key,
    );
  }

  final Object? id;
  final String name;
  final String key;

  JsonMap toJson() => {'id': id, 'name': name, 'key': key};
}

/// Admin-managed interests form of this app (`GET /interests/form`).
class InterestForm {
  const InterestForm({required this.app, required this.questions});

  factory InterestForm.fromResponse(dynamic body) =>
      InterestForm.fromJson(_payload(body, 'questions'));

  /// Also reads the disk copy written by [toJson].
  factory InterestForm.fromJson(Object? json) {
    final m = _asMap(json);
    return InterestForm(
      app: InterestApp.fromJson(m['app']),
      questions: [
        if (m['questions'] is List)
          for (final q in m['questions'] as List) InterestQuestion.fromJson(q),
      ].where((q) => q.key.isNotEmpty).toList(),
    );
  }

  final InterestApp app;
  final List<InterestQuestion> questions;

  InterestQuestion? question(String key) {
    for (final q in questions) {
      if (q.key == key) return q;
    }
    return null;
  }

  /// The onboarding language question with its live options, or null when
  /// this platform should not ask it (RN `findLanguageQuestion`).
  InterestQuestion? get languageQuestion {
    final q = question(LanguageStep.questionKey);
    if (q == null || q.isDeprecated || q.isHidden) return null;
    final options = q.options.where((o) => !o.isDeprecated).toList();
    return options.isEmpty ? null : q.copyWith(options: options);
  }

  JsonMap toJson() => {
    'app': app.toJson(),
    'questions': [for (final q in questions) q.toJson()],
  };
}

/// The signed-in user's answers (`GET /me/interests`).
class MyInterests {
  const MyInterests({required this.app, required this.selections});

  factory MyInterests.fromResponse(dynamic body) {
    final m = _payload(body, 'selections');
    return MyInterests(
      app: InterestApp.fromJson(m['app']),
      selections: normalizeInterestSelections(m['selections']),
    );
  }

  final InterestApp app;
  final InterestSelections selections;
}

/// `PUT /me/interests` answer.
class SaveInterestsResult {
  const SaveInterestsResult({
    required this.appKey,
    required this.savedCount,
    required this.selections,
    this.message,
  });

  factory SaveInterestsResult.fromResponse(dynamic body) {
    final m = _asMap(body);
    return SaveInterestsResult(
      message: J.str(m['message']),
      appKey: J.str(m['appKey']) ?? Env.appPlatform,
      savedCount: J.integer(m['savedCount']) ?? 0,
      selections: normalizeInterestSelections(m['selections']),
    );
  }

  /// Server's confirmation text, if any (the UI has its own copy).
  final String? message;
  final String appKey;
  final int savedCount;
  final InterestSelections selections;
}

/// Post-login question "Which languages should your expert speak?".
enum LanguageStepStatus {
  /// Not checked yet for this sign-in.
  unknown,
  required,
  done,
}

/// Rules of the onboarding language step (RN `languageStep.service.js`).
abstract final class LanguageStep {
  static const questionKey = 'expert_language';

  /// Starting selection on the language screen: the saved answer limited to
  /// the live options, else the option(s) the admin marked as default.
  static List<String> initialSelection(
    InterestQuestion question,
    List<String>? saved,
  ) {
    final allowed = {for (final o in question.options) o.value};
    final kept = [...?saved?.where(allowed.contains)];
    if (kept.isNotEmpty) return kept;
    final defaults = [
      for (final o in question.options)
        if (o.isDefault) o.value,
    ];
    final max = question.maxSelect;
    return max != null && defaults.length > max
        ? defaults.sublist(0, max)
        : defaults;
  }

  /// Starting selection over the Languages collection ([languages]: value =
  /// documentId, label = `languageNames`). Saved values that are still
  /// languages are kept; one saved from the old form options (`English`,
  /// `lang_hindi`) is kept when its value or its form label names a
  /// language. Nothing kept: the form's default option(s), matched by name.
  /// Capped at the form's `maxSelect`.
  static List<String> initialFromCatalog({
    required List<InterestOption> languages,
    required InterestQuestion form,
    List<String>? saved,
  }) {
    String key(String v) => v.trim().toLowerCase();
    final ids = {for (final l in languages) l.value};
    final byName = <String, String>{};
    for (final l in languages) {
      byName.putIfAbsent(key(l.label), () => l.value);
    }
    final formLabels = {for (final o in form.options) o.value: o.label};
    String? resolve(String v) => ids.contains(v)
        ? v
        : byName[key(v)] ?? byName[key(formLabels[v] ?? '')];

    List<String> capped(Iterable<String?> values) {
      final out = <String>{for (final v in values) ?v}.toList();
      final max = form.maxSelect;
      return max != null && out.length > max ? out.sublist(0, max) : out;
    }

    final kept = capped([...?saved?.map(resolve)]);
    if (kept.isNotEmpty) return kept;
    return capped([
      for (final o in form.options)
        if (o.isDefault) resolve(o.value),
    ]);
  }

  /// Payload for PUT /me/interests, which replaces the whole answer set and
  /// validates every required question, even ones the app no longer asks:
  /// current answers + the languages + a neutral answer for any unanswered
  /// required question that has one.
  static InterestSelections buildSelections({
    required InterestSelections existing,
    required List<String> languages,
    InterestForm? form,
  }) {
    final selections = <String, List<String>>{
      ...existing,
      questionKey: languages,
    };
    for (final q in form?.questions ?? const <InterestQuestion>[]) {
      if (!q.required ||
          q.key == questionKey ||
          (selections[q.key]?.isNotEmpty ?? false)) {
        continue;
      }
      final neutral = q.neutralAnswer;
      if (neutral.isNotEmpty) selections[q.key] = neutral;
    }
    return selections;
  }
}

/// What the language screen shows.
class LanguageQuestionData {
  const LanguageQuestionData({this.question, this.selected = const []});

  /// Null when the form no longer asks it: skip the step.
  final InterestQuestion? question;
  final List<String> selected;
}
