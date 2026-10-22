import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/log.dart';
import '../../../component/c_toast.dart';
import 'host_profile_rules.dart';

/// Opens a host's social / website link in its app or the browser.
Future<void> openExternalLink(String url) async {
  final uri = HostProfileRules.externalUri(url);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.w('HostProfile', 'cannot open $url: $e');
    }
  }
  if (!opened) {
    CToast.show('host:social.open_failed', variant: CToastVariant.error);
  }
}
