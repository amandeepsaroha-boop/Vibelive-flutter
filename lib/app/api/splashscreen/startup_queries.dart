import 'dart:async';

import '../../../core/query/query_hooks.dart';
import '../../../core/session/session_store.dart';
import '../authscreen/interests_queries.dart';
import '../callscreen/call_queries.dart';
import '../client/client_queries.dart';
import '../homescreen/home_queries.dart';
import '../hosthub/hosthub_queries.dart';
import '../paymentscreen/payment_queries.dart';
import '../paymentscreen/runtime_config_queries.dart';
import '../resourcesscreen/resources_queries.dart';
import 'splash_queries.dart';

/// Warms what the first screens after the splash / login show, all in
/// parallel (no request waits on another): Home (feed, popular, wallet
/// chip), ME (profile, host stats), History page 1, the interests form,
/// app-config, pricing and GST config, the menu pages, and a host's own
/// profile (Host Hub, editor prefill). Each lands in the cache under the
/// key its screen reads, so those screens open on data; anything still in
/// flight is joined, never sent twice. Failures are ignored: the screens
/// fetch on their own.
void prefetchStartup() {
  final session = SessionStore.instance.value;
  final uid = session.userDocumentId;
  if (!session.isAuthenticated || uid == null) return;
  RuntimeConfigRefresher.start();
  final expertId = session.expertDocumentId ?? session.expertId?.toString();
  for (final Future<Object?> f in [
    ensureAppConfig(),
    ensureMyProfile(uid),
    ensureWalletBalance(userDocumentId: uid, staleDuration: StaleTime.short),
    ensureCallHistory(uid),
    ensureInterestForm(),
    ensurePricingConfig(),
    ensureGstConfig(),
    ensureMenuPages(),
    if (session.isExpert) ensureHostStats(uid),
    if (session.isExpert && expertId != null) ensureHostProfile(expertId),
  ]) {
    unawaited(f.then((_) {}, onError: (Object _) {}));
  }
  prefetchDiscover();
}
