import 'package:flutter/widgets.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/utils/log.dart';
import '../hosthub/catalog_models.dart';
import 'auth_api.dart';
import 'auth_errors.dart';
import 'auth_keys.dart';
import 'auth_models.dart';
import 'interests_api.dart';
import 'interests_models.dart';
import 'interests_queries.dart';
import 'languages_queries.dart';

// Post-login steps: the 18+ gate, then the language question
// (RN `ageGate.service.js`, `languageStep.service.js`).
//
// The age verdict lives on the session user (`SessionState.ageGateStatus`),
// so it survives restarts and updates with it. The language step status is
// a cached query, re-checked for every sign-in.

/// Where the signed-in user belongs now (RN `decidePostAuthRoute`, without
/// the navigation). Never throws.
///
/// [confirmAgeGate]: cold start. The stored verdict may be stale (date
/// entered on another device, account blocked since), so anything but `ok`
/// is confirmed with the server.
Future<OnboardingStep> nextOnboardingStep({bool confirmAgeGate = false}) async {
  final session = SessionStore.instance.value;
  if (!session.isAuthenticated) return OnboardingStep.signedOut;
  var age = session.ageGateStatus;
  if (age == AgeGateStatus.unknown ||
      (confirmAgeGate && age != AgeGateStatus.ok)) {
    age = await syncAgeGateStatus();
  }
  if (age.gates) return OnboardingStep.ageGate;
  // Only asked once the age gate is passed.
  final language = await ensureLanguageStepStatus();
  return language == LanguageStepStatus.required
      ? OnboardingStep.language
      : OnboardingStep.home;
}

// ── Age gate ─────────────────────────────────────────────────────────────

/// Confirms the 18+ verdict with GET /me and stores it on the session user.
/// Never throws: if /me fails the stored verdict stands, and `unknown` never
/// gates, so a network blip cannot lock anyone out.
Future<AgeGateStatus> syncAgeGateStatus() async {
  final store = SessionStore.instance;
  final userKey = store.value.userKey;
  if (userKey == null) return AgeGateStatus.unknown;
  try {
    final me = await AuthApi.fetchMe();
    final status = AgeGate.resolve(me);
    // Ignore a late answer for an account that has since signed out or
    // switched, and an answer without the age fields.
    if (me != null &&
        status != AgeGateStatus.unknown &&
        store.value.userKey == userKey) {
      await store.updateUser({
        ...AgeGate.fieldsOf(me),
        'ageGateStatus': status.name,
      });
    }
  } on ApiException catch (e) {
    Log.w('Onboarding', 'age status not confirmed; keeping the stored one: $e');
  }
  return store.value.ageGateStatus;
}

/// [isoDate] comes from `DateOfBirthCheck`. Succeeds with `ok`, or `blocked`
/// (under 18, terminal; the session user is updated either way).
MutationResult<AgeGateStatus, ApiException, String> useSaveDateOfBirthMutation({
  List<RawQueryKey> invalidates = const [],
  void Function(AgeGateStatus verdict)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<AgeGateStatus, String>(
  saveDateOfBirth,
  invalidates: [AuthKeys.users, AuthKeys.sessionUser, ...invalidates],
  onSuccess: (verdict, _) => onSuccess?.call(verdict),
  onError: (e, _) => onError?.call(e),
);

Future<AgeGateStatus> saveDateOfBirth(String isoDate) async {
  final verdict = await AuthApi.submitDateOfBirth(isoDate);
  final store = SessionStore.instance;
  // Persisted with the user, so the next cold start does not ask again.
  if (store.value.isAuthenticated) {
    await store.updateUser(
      verdict == AgeGateStatus.blocked
          ? {'age_blocked': true, 'ageGateStatus': verdict.name}
          : {
              'date_of_birth': isoDate,
              'age_verified_at': DateTime.now().toUtc().toIso8601String(),
              'age_blocked': false,
              'ageGateStatus': verdict.name,
            },
    );
  }
  return verdict;
}

// ── Language step ────────────────────────────────────────────────────────

/// Bound on each check, so a slow server never holds the app on the splash.
const _checkTimeout = Duration(seconds: 6);

QueryResult<LanguageStepStatus, ApiException> useLanguageStepStatus(
  BuildContext context,
) {
  final userKey = SessionStore.instance.value.userKey;
  return useApiQuery<LanguageStepStatus>(
    AuthKeys.languageStep(userKey ?? ''),
    () => _checkLanguageStep(userKey!),
    context: context,
    enabled: userKey != null,
    staleDuration: StaleTime.static,
  );
}

/// Whether the signed-in user still has to answer the language question.
/// Checked once per sign-in (the cache is cleared on sign-out). Never throws.
Future<LanguageStepStatus> ensureLanguageStepStatus() async {
  final store = SessionStore.instance;
  final userKey = store.value.userKey;
  if (userKey == null) return LanguageStepStatus.unknown;
  final status = await queryCache.fetchQuery<LanguageStepStatus>(
    AuthKeys.languageStep(userKey),
    () => _checkLanguageStep(userKey),
    staleDuration: StaleTime.static,
  );
  // A late answer for an account that has since signed out or switched.
  return store.value.userKey == userKey ? status : LanguageStepStatus.unknown;
}

Future<LanguageStepStatus> _checkLanguageStep(String userKey) async {
  // Shown once per account: answered, skipped, or not asked.
  if (_isLanguageStepDone(userKey)) return LanguageStepStatus.done;
  try {
    // The answers are read alongside the form, not after it (the splash
    // waits on this).
    final answers = ensureMyInterests().withApiTimeout(_checkTimeout)..ignore();
    final question = (await _loadForm()).languageQuestion;
    if (question == null) return LanguageStepStatus.done;
    final mine = await answers;
    if (mine.selections[LanguageStep.questionKey]?.isNotEmpty ?? false) {
      await _persistLanguageStepDone(userKey);
      return LanguageStepStatus.done;
    }
    return LanguageStepStatus.required;
  } catch (e) {
    // Deliberate (RN): a check that cannot reach the server never blocks the
    // app. Not persisted, so the next launch checks again.
    Log.w('Onboarding', 'language step check failed; not blocking: $e');
    return LanguageStepStatus.done;
  }
}

/// What the language screen needs: the form's question (title, help,
/// required, min/max) with its options replaced by the Languages collection
/// (`/languages`, A→Z; value = the language's documentId). Throws when either
/// cannot load, so the screen can offer a retry.
QueryResult<LanguageQuestionData, ApiException> useLanguageQuestion(
  BuildContext context,
) {
  final userKey = SessionStore.instance.value.userKey;
  return useApiQuery<LanguageQuestionData>(
    AuthKeys.languageQuestion(userKey ?? ''),
    loadLanguageQuestion,
    context: context,
    enabled: userKey != null,
    staleDuration: StaleTime.short,
  );
}

Future<LanguageQuestionData> loadLanguageQuestion() async {
  // Form, catalog and saved answers are independent: read in parallel.
  final catalog = ensureLanguages().withApiTimeout(_checkTimeout)..ignore();
  final answers = ensureMyInterests().withApiTimeout(_checkTimeout)..ignore();
  final form = (await _loadForm()).languageQuestion;
  if (form == null) return const LanguageQuestionData();
  final languages = [for (final l in await catalog) ?_languageOption(l)];
  // Nothing to pick from: nothing to ask.
  if (languages.isEmpty) return const LanguageQuestionData();
  List<String>? saved;
  try {
    final mine = await answers;
    saved = mine.selections[LanguageStep.questionKey];
  } on ApiException catch (e) {
    // Deliberate (RN): pre-selection is a nicety; the question itself loaded.
    Log.w('Onboarding', 'saved languages not loaded: $e');
  }
  return LanguageQuestionData(
    question: form.copyWith(options: languages),
    selected: LanguageStep.initialFromCatalog(
      languages: languages,
      form: form,
      saved: saved,
    ),
  );
}

/// A Languages row as a choice: documentId (Strapi v5's relation id), else
/// the numeric id.
InterestOption? _languageOption(HostOption language) {
  final value = language.documentId ?? language.id?.toString();
  return value == null
      ? null
      : InterestOption(value: value, label: language.label);
}

/// Saves the chosen languages (Languages documentIds, already within the
/// question's min/max) as the `expert_language` answer and completes the
/// step. Succeeds with false when the server refused the
/// answer set (400/422): the step completes anyway so the user is never
/// trapped. Network, timeout, 5xx and 429 throw (retryable).
MutationResult<bool, ApiException, List<String>> useSaveLanguagesMutation({
  void Function(bool saved)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<bool, List<String>>(
  saveLanguageStep,
  invalidates: const [
    AuthKeys.myInterestsAll,
    AuthKeys.languageSteps,
    AuthKeys.languageQuestions,
  ],
  onSuccess: (saved, _) => onSuccess?.call(saved),
  onError: (e, _) => onError?.call(e),
);

Future<bool> saveLanguageStep(List<String> languages) async {
  final userKey = SessionStore.instance.value.userKey;
  try {
    // Must be fresh and must succeed: the PUT replaces the whole answer set,
    // so saving without the current answers could wipe them.
    final existing = await ensureMyInterests(
      staleDuration: StaleTime.none,
    ).withApiTimeout(_checkTimeout);
    await InterestsApi.saveMyInterests(
      LanguageStep.buildSelections(
        existing: existing.selections,
        languages: languages,
        form: cachedInterestForm(),
      ),
    );
    await _completeLanguageStep(userKey);
    return true;
  } on ApiException catch (e) {
    if (e.statusCode == 400 || e.statusCode == 422) {
      Log.w(
        'Onboarding',
        'language answer refused; continuing without it: '
            '${e.interestErrorCode ?? e}',
      );
      await _completeLanguageStep(userKey);
      return false;
    }
    throw AuthErrors.languageSave(e);
  }
}

/// User skipped (offered only while the question is optional). Never throws.
Future<void> skipLanguageStep() =>
    _completeLanguageStep(SessionStore.instance.value.userKey);

/// Fresh form, else the last one seen on this device (RN `loadForm`).
Future<InterestForm> _loadForm() async {
  try {
    return await ensureInterestForm().withApiTimeout(_checkTimeout);
  } on ApiException {
    final cached = cachedInterestForm();
    if (cached != null) return cached;
    rethrow;
  }
}

String _doneKey(String userKey) => 'language_step_done:$userKey';

bool _isLanguageStepDone(String userKey) =>
    AppPrefs.getString(_doneKey(userKey)) != null;

Future<void> _persistLanguageStepDone(String userKey) =>
    AppPrefs.setString(_doneKey(userKey), '1');

Future<void> _completeLanguageStep(String? userKey) async {
  if (userKey != null) await _persistLanguageStepDone(userKey);
  queryCache.invalidateAll(const [AuthKeys.languageSteps]);
}
