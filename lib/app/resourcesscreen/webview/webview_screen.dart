import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/network_status.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../authscreen/helper/campaign_links.dart';
import '../../component/c_state_view.dart';
import '../../component/c_toast.dart';
import '../../component/status_bar_style.dart';
import '../helper/resource_links.dart';
import 'webview_header.dart';

enum _Load { opening, failed, offline }

/// `/webview?url=…&title=…` (RN `AppWebViewScreen`), opened by the
/// `webview` campaign preset.
///
/// The app ships no WebView plugin, so the page opens in the in-app browser
/// view (SFSafariViewController / Custom Tabs): same sandbox, same "stay in
/// the app" feel. Once it is up, this screen steps aside so closing the
/// browser lands where the user came from (Home after a cold-start push).
class WebviewScreen extends HookWidget {
  const WebviewScreen({super.key, this.url, this.title});

  final String? url;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final startUrl = useMemoized(() => CampaignLinks.webUrl(url), [url]);
    final load = useState(_Load.opening);

    void leave() {
      if (!context.mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.home);
      }
    }

    Future<void> open() async {
      final target = startUrl;
      if (target == null) return;
      load.value = _Load.opening;
      final ok = await ResourceLinks.tryOpen(
        Uri.parse(target),
        mode: LaunchMode.inAppBrowserView,
      );
      if (!context.mounted) return;
      if (ok) return leave();
      load.value = NetworkStatus.instance.value ? _Load.failed : _Load.offline;
    }

    Future<void> openExternally() async {
      final target = startUrl;
      if (target == null) return;
      final ok = await ResourceLinks.tryOpen(Uri.parse(target));
      if (!ok) {
        CToast.show('resources:webview.no_app', variant: CToastVariant.error);
      }
    }

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (startUrl == null) {
          // A missing / non-http(s) url: say so and leave.
          CToast.show(
            'resources:webview.invalid',
            variant: CToastVariant.error,
          );
          leave();
        } else {
          open();
        }
      });
      return null;
    }, const []);

    final c = context.colors;
    final fixedTitle = title?.trim() ?? '';
    final host = startUrl == null ? null : CampaignLinks.hostOf(startUrl);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: c.isDark ? c.bg : c.background,
        body: Column(
          children: [
            SafeArea(
              bottom: false,
              child: WebviewHeader(
                title: fixedTitle,
                host: host,
                secure: startUrl?.toLowerCase().startsWith('https://') ?? false,
                onBack: leave,
                onReload: open,
                onExternal: openExternally,
              ),
            ),
            SizedBox(
              height: 2.5,
              child: load.value == _Load.opening && startUrl != null
                  ? LinearProgressIndicator(
                      minHeight: 2.5,
                      color: c.accent,
                      backgroundColor: c.bg.withValues(alpha: 0),
                    )
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: switch (load.value) {
                  _Load.opening => _Opening(host: host),
                  _Load.failed => CStateView(
                    title: 'resources:webview.failed_title',
                    message: 'resources:webview.failed_message',
                    icon: LucideIcons.triangleAlert,
                    actionLabel: 'actions.retry',
                    onAction: open,
                  ),
                  _Load.offline => CStateView(
                    title: 'resources:webview.offline_title',
                    message: 'resources:webview.offline_message',
                    icon: LucideIcons.wifiOff,
                    actionLabel: 'actions.retry',
                    onAction: open,
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// While the browser view comes up.
class _Opening extends StatelessWidget {
  const _Opening({this.host});
  final String? host;

  @override
  Widget build(BuildContext context) => CStateView(
    title: 'resources:webview.opening',
    message: host,
    translateMessage: false,
    icon: LucideIcons.globe,
  );
}
