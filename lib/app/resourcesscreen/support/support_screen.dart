import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/me_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/device_info.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/resourcesscreen/resources_models.dart';
import '../../api/splashscreen/splash_queries.dart';
import '../../component/c_button.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/pressable.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../helper/resource_links.dart';
import '../helper/resource_palette.dart';
import '../widgets/page_body.dart';
import '../widgets/sub_page_header.dart';

/// `/me/support` (Resources → Help & Support): the support email, with
/// "Email us" (opens the mail app, subject and account filled in) and Copy.
/// The address is app-config's `supportEmail`, else
/// [SupportContact.defaultEmail].
class SupportScreen extends HookWidget {
  const SupportScreen({super.key});

  /// The mail, ready to send: who is writing and from which app, so the team
  /// can find the account without asking.
  static Uri mailUri(BuildContext context, String email) {
    final session = SessionStore.instance.value;
    final account = session.userDocumentId;
    final body = [
      '',
      '',
      '—',
      if (account != null)
        context.t('resources:support.mail_account', variables: {'id': account}),
      context.t(
        'resources:support.mail_app',
        variables: {'platform': DeviceInfo.platform},
      ),
    ].join('\n');
    final query = [
      'subject=${Uri.encodeComponent(context.t('resources:support.mail_subject'))}',
      'body=${Uri.encodeComponent(body)}',
    ].join('&');
    return Uri(scheme: 'mailto', path: email, query: query);
  }

  @override
  Widget build(BuildContext context) {
    final config = useAppConfig(context).data;
    final email = config == null
        ? SupportContact.defaultEmail
        : SupportContact.fromAppConfig(config).emailOrDefault;
    final p = ResourcePalette.of(context);
    final accent = context.colors.accent;
    final bottom = MediaQuery.paddingOf(context).bottom;

    Future<void> copy({bool noMailApp = false}) async {
      await Clipboard.setData(ClipboardData(text: email));
      CToast.show(
        noMailApp
            ? 'resources:support.no_mail_app'
            : 'resources:support.copied',
        variant: noMailApp ? CToastVariant.info : CToastVariant.success,
      );
    }

    Future<void> write() async {
      ResourceEvents.supportContact('email');
      final opened = await ResourceLinks.tryOpen(mailUri(context, email));
      // No mail app: the address is on the clipboard to paste anywhere.
      if (!opened) await copy(noMailApp: true);
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SubPageHeader(title: 'resources:support.title'),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20.ms,
                        16.ms,
                        20.ms,
                        40.ms + bottom,
                      ),
                      child: PageCard(
                        child: Column(
                          children: [
                            SizedBox(height: 8.ms),
                            Container(
                              width: 64.ms,
                              height: 64.ms,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.colors.accentA(0.14),
                              ),
                              child: Icon(
                                LucideIcons.mail,
                                size: 28.ms,
                                color: accent,
                              ),
                            ),
                            SizedBox(height: 16.ms),
                            CText(
                              'resources:support.heading',
                              size: 20,
                              weight: FontWeight.w800,
                              color: p.text,
                              align: TextAlign.center,
                            ),
                            SizedBox(height: 8.ms),
                            CText(
                              'resources:support.body',
                              size: 14,
                              height: 21,
                              weight: FontWeight.w500,
                              color: p.muted,
                              align: TextAlign.center,
                            ),
                            SizedBox(height: 20.ms),
                            _EmailRow(email: email, onTap: write, onCopy: copy),
                            SizedBox(height: 16.ms),
                            CButton(
                              title: 'resources:support.email_us',
                              icon: Icon(
                                LucideIcons.send,
                                size: 18.ms,
                                color: context.colors.onAccent,
                              ),
                              showArrow: false,
                              onPressed: write,
                            ),
                            SizedBox(height: 14.ms),
                            CText(
                              'resources:support.tip',
                              size: 12.5,
                              height: 18,
                              weight: FontWeight.w500,
                              color: p.muted,
                              align: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The address itself (tap: write) with a Copy button.
class _EmailRow extends StatelessWidget {
  const _EmailRow({
    required this.email,
    required this.onTap,
    required this.onCopy,
  });

  final String email;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(14.ms, 6.ms, 6.ms, 6.ms),
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(14.ms),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Pressable(
              onPressed: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8.ms),
                child: CText.raw(
                  email,
                  size: 15,
                  weight: FontWeight.w700,
                  color: ResourcePalette.link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          Pressable(
            onPressed: onCopy,
            semanticLabel: context.t('resources:support.copy'),
            child: Container(
              height: 36.ms,
              padding: EdgeInsets.symmetric(horizontal: 12.ms),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(10.ms),
                border: Border.all(color: p.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.copy, size: 15.ms, color: p.text),
                  SizedBox(width: 6.ms),
                  CText(
                    'resources:support.copy',
                    size: 13,
                    weight: FontWeight.w700,
                    color: p.text,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
