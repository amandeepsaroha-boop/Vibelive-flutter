import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import 'instant_call_api.dart';
import 'instant_call_models.dart';

/// Whether Talk Now is on for the signed-in user (per user: the admin gives
/// it to company accounts or to all). Off while unknown. Read again each
/// time the app comes back to the foreground, so an admin switch shows
/// without restarting the app (the home screen stays mounted).
QueryResult<InstantCallConfig, ApiException> useInstantCallConfig(
  BuildContext context,
) {
  final session = useValueListenable(SessionStore.instance);
  final result = useApiQuery<InstantCallConfig>(
    ['instant-call', 'config', session.userDocumentId ?? ''],
    InstantCallApi.fetchConfig,
    context: context,
    enabled: session.isAuthenticated,
    staleDuration: StaleTime.short,
  );
  final refetch = useRef(result.refetch)..value = result.refetch;
  useOnAppLifecycleStateChange((_, state) {
    if (state == AppLifecycleState.resumed && session.isAuthenticated) {
      refetch.value();
    }
  });
  return result;
}
