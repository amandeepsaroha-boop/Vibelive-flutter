import 'package:url_launcher/url_launcher.dart';

import '../../../../core/analytics/events/discover_events.dart';
import '../../../../core/utils/log.dart';
import '../../../component/c_toast.dart';
import 'host_profile_rules.dart';

/// Opens a host's social / website link in its app or the browser.
/// [kind] / [hostId] / [source]: for analytics.
Future<void> openExternalLink(
  String url, {
  String kind = 'link',
  String? hostId,
  String source = 'profile_sheet',
}) async {
  final uri = HostProfileRules.externalUri(url);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.w('HostProfile', 'cannot open $url: $e');
    }
  }
  DiscoverEvents.externalLinkTapped(
    hostId: hostId,
    kind: kind,
    source: source,
    opened: opened,
  );
  if (!opened) {
    CToast.show('host:social.open_failed', variant: CToastVariant.error);
  }
}
