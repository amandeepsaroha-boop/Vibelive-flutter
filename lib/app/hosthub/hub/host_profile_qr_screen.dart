import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/analytics/events/host_events.dart';
import '../../../core/session/session_store.dart';
import '../../api/client/client_models.dart';
import '../../authscreen/helper/link_parser.dart';
import '../../component/qr_code_sheet.dart';
import '../common/host_page.dart';
import '../onboarding/helper/host_palette.dart';

/// `/me/profile-qr` (RN ProfileQrCodeScreen): the existing QR sheet over a
/// blank page, which closes with it. Links and menus keep using the route.
class HostProfileQrScreen extends HookWidget {
  const HostProfileQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        final s = SessionStore.instance.value;
        final me = UserWithExpert(user: s.user ?? const {}, expert: s.expert);
        final slug = me.shareSlug;
        HostEvents.qrOpened(hasLink: slug != null);
        if (slug != null) {
          await showQrCodeSheet(
            context,
            url: LinkParser.shareLink(slug),
            name: me.name ?? '',
            handle: me.handler ?? '',
          );
        }
        if (context.mounted) HostPage.leave(context);
      });
      return null;
    }, const []);
    return Scaffold(backgroundColor: HostPalette.of(context).bg);
  }
}
