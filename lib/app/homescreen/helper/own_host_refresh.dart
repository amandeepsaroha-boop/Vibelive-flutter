import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/query/query_client.dart';
import '../../../core/session/session_store.dart';
import '../../api/client/client_queries.dart';
import 'home_controller.dart';

/// RN Discovery `refreshOwnExpert`: a host's own profile is re-read when
/// Discover shows (open, tab switch, app resume) so the top bar's review
/// state reflects decisions made since login. At most once a minute; a
/// failure keeps the cached copy.
void useOwnHostRefresh(HomeController home) {
  final last = useRef<DateTime?>(null);
  useEffect(() {
    void refresh() {
      if (home.tab.value != HomeTab.discover) return;
      final session = SessionStore.instance.value;
      final uid = session.userDocumentId;
      if (!session.isExpert || uid == null) return;
      final now = DateTime.now();
      final at = last.value;
      if (at != null && now.difference(at) < const Duration(minutes: 1)) {
        return;
      }
      last.value = now;
      // Syncs the session (and so the bar) when something changed.
      ensureMyProfile(uid, staleDuration: StaleTime.none).ignore();
    }

    refresh();
    home.tab.addListener(refresh);
    final life = AppLifecycleListener(onResume: refresh);
    return () {
      home.tab.removeListener(refresh);
      life.dispose();
    };
  }, [home]);
}
