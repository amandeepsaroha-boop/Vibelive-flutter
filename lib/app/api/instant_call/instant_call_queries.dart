import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'instant_call_api.dart';
import 'instant_call_models.dart';

/// Whether Talk Now is on for the signed-in user (per user: it can be
/// staff-only). Off while unknown.
QueryResult<InstantCallConfig, ApiException> useInstantCallConfig(
  BuildContext context,
) {
  final session = useValueListenable(SessionStore.instance);
  return useApiQuery<InstantCallConfig>(
    ['instant-call', 'config', session.userDocumentId ?? ''],
    InstantCallApi.fetchConfig,
    context: context,
    enabled: session.isAuthenticated,
    staleDuration: StaleTime.medium,
  );
}
