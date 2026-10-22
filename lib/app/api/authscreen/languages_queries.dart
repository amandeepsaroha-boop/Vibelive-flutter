import 'package:flutter/widgets.dart';

import '../../../core/query/query_hooks.dart';
import '../hosthub/catalog_models.dart';
import 'auth_keys.dart';
import 'languages_api.dart';

/// The Languages collection, A→Z (reference data: cached for hours).
QueryResult<List<HostOption>, ApiException> useLanguages(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<List<HostOption>>(
  AuthKeys.languages,
  LanguagesApi.fetchAll,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.static,
);

/// Outside widgets (the onboarding language step).
Future<List<HostOption>> ensureLanguages() =>
    queryCache.fetchQuery<List<HostOption>>(
      AuthKeys.languages,
      LanguagesApi.fetchAll,
      staleDuration: StaleTime.static,
    );
