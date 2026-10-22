import 'package:flutter/widgets.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/session/session_store.dart';
import 'auth_keys.dart';
import 'auth_models.dart';
import 'interests_api.dart';
import 'interests_models.dart';

/// The interests form, kept on disk as RN did: onboarding and support topics
/// still have it when offline.
QueryResult<InterestForm, ApiException> useInterestForm(
  BuildContext context, {
  bool enabled = true,
}) => usePersistedQuery<InterestForm>(
  AuthKeys.interestForm,
  InterestsApi.fetchForm,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.long,
  toJson: (form) => form.toJson(),
  fromJson: InterestForm.fromJson,
);

/// Outside widgets (onboarding checks, support topics).
Future<InterestForm> ensureInterestForm() =>
    queryCache.fetchQuery<InterestForm>(AuthKeys.interestForm, () async {
      final form = await InterestsApi.fetchForm();
      QueryPersist.write(AuthKeys.interestForm, form.toJson());
      return form;
    }, staleDuration: StaleTime.long);

/// Last form seen, without a request (RN `getCachedForm`): memory, then disk.
InterestForm? cachedInterestForm() =>
    queryCache.getQueryData<InterestForm, ApiException>(
      AuthKeys.interestForm,
    ) ??
    QueryPersist.read<InterestForm>(
      AuthKeys.interestForm,
      InterestForm.fromJson,
    );

/// The signed-in user's answers.
QueryResult<MyInterests, ApiException> useMyInterests(
  BuildContext context, {
  bool enabled = true,
}) {
  final userKey = SessionStore.instance.value.userKey;
  return useApiQuery<MyInterests>(
    AuthKeys.myInterests(userKey ?? ''),
    InterestsApi.fetchMyInterests,
    context: context,
    enabled: enabled && userKey != null,
    staleDuration: StaleTime.short,
  );
}

Future<MyInterests> ensureMyInterests({
  Duration staleDuration = StaleTime.short,
}) async {
  final userKey = SessionStore.instance.value.userKey;
  if (userKey == null) throw const ApiException(ApiErrorType.unauthorized);
  return queryCache.fetchQuery<MyInterests>(
    AuthKeys.myInterests(userKey),
    InterestsApi.fetchMyInterests,
    staleDuration: staleDuration,
  );
}

/// Saves the whole answer set. [invalidates]: other keys that show answers.
MutationResult<SaveInterestsResult, ApiException, InterestSelections>
useSaveInterestsMutation({
  String source = 'onboarding',
  List<RawQueryKey> invalidates = const [],
  void Function(SaveInterestsResult result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<SaveInterestsResult, InterestSelections>(
  (selections) => InterestsApi.saveMyInterests(selections, source: source),
  // The answers include the onboarding language, so that step re-checks.
  invalidates: [
    AuthKeys.myInterestsAll,
    AuthKeys.languageSteps,
    AuthKeys.languageQuestions,
    ...invalidates,
  ],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);
