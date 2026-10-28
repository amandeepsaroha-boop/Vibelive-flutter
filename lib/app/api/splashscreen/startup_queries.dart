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

/// Warms what the first screens after the splash / login show. Each lands
/// in the cache under the key its screen reads, so those screens open on
/// data; anything still in flight is joined, never sent twice. Failures are
/// ignored: the screens fetch on their own.
///
/// Feed first, the rest after it: sent together, the ~15 reads shared the
/// server and the feed (the screen the user lands on) came back last, in
/// 3.5-6.5 s instead of well under one (device log, 2026-10-28). Home's
/// header (wallet chip, profile, a host's own profile) goes right after the
/// feed; History, the ME tab, the sheets' configs and the menu wait until
/// feed page 1 is in, or failed.
void prefetchStartup() {
  final session = SessionStore.instance.value;
  final uid = session.userDocumentId;
  if (!session.isAuthenticated || uid == null) return;
  RuntimeConfigRefresher.start();
  final expertId = session.expertDocumentId ?? session.expertId?.toString();
  final feed = prefetchDiscover();
  _quietly([
    ensureMyProfile(uid),
    ensureWalletBalance(userDocumentId: uid, staleDuration: StaleTime.short),
    if (session.isExpert && expertId != null) ensureHostProfile(expertId),
  ]);
  unawaited(
    feed.whenComplete(
      () => _quietly([
        ensureAppConfig(),
        ensureCallHistory(uid),
        ensureInterestForm(),
        ensurePricingConfig(),
        ensureGstConfig(),
        ensureMenuPages(),
        if (session.isExpert) ensureHostStats(uid),
      ]),
    ),
  );
}

void _quietly(List<Future<Object?>> reads) {
  for (final f in reads) {
    unawaited(f.then((_) {}, onError: (Object _) {}));
  }
}
