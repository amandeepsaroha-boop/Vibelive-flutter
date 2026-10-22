import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_toast.dart';
import '../../../hosthub/hub/host_hub_menu.dart';
import '../../../hosthub/onboarding/helper/intro_image.dart';
import '../helper/host_unlock_promo.dart';
import '../helper/me_actions.dart';
import '../helper/me_data.dart';
import '../helper/me_menu.dart';
import '../helper/me_palette.dart';
import 'host_unlock_row.dart';
import 'me_rows.dart';

/// The settings list (RN MeCard, Settings section), as a sliver: wallet,
/// IDENTITY and HOST HUB options inline, RESOURCES as a card that opens its
/// sub-menu. Clients always see it; hosts on the Settings tab.
class MeSettingsList extends HookWidget {
  const MeSettingsList({super.key, required this.data});
  final MeData data;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final userKey = data.userKey;
    final seen = useMemoized(() => HostUnlockPromo.seen(userKey), [userKey]);
    final dismissed = useState(false);
    final promo =
        !data.isExpert &&
        data.isPersonalInfoComplete &&
        !seen &&
        !dismissed.value;

    void markSeen() {
      dismissed.value = true;
      HostUnlockPromo.markSeen(userKey).ignore();
    }

    Future<void> becomeHost() async {
      if (!data.isPersonalInfoComplete) {
        // Explain instead of a dead row: say what is missing, go fill it in.
        final fields = data.missingPersonalInfo
            .map((f) => context.t(f.i18nKey))
            .join(', ');
        final go = await CAlert.confirm(
          title: 'client:me.become_host_locked.title',
          message: 'client:me.become_host_locked.message',
          variables: {'fields': fields},
          confirmLabel: 'client:me.become_host_locked.action',
          variant: CAlertVariant.info,
        );
        if (go && context.mounted) {
          await MeActions.open(context, AppRoutes.personalInfo);
        }
        return;
      }
      if (promo) markSeen();
      // Decode the intro photo first so it never pops in.
      await HostIntroImage.precache(context);
      if (context.mounted) {
        await MeActions.open(context, AppRoutes.hostOnboarding);
      }
    }

    Future<void> shareProfile() async {
      final link = data.profileLink;
      if (link == null) {
        CToast.show(
          'client:me.share.unavailable',
          variant: CToastVariant.error,
        );
        return;
      }
      await MeActions.share(
        context.t('client:me.share.message', variables: {'link': link}),
      );
    }

    void tap(MeMenuItem item) {
      switch (item.id) {
        case MeItemId.share:
          shareProfile();
        case MeItemId.becomeHost:
          becomeHost();
        case MeItemId.verification:
          MeActions.open(context, data.verificationRoute);
        case MeItemId.route:
          MeActions.open(context, item.route!);
      }
    }

    final badgeKey = data.badgePromptKey;
    Widget row(MeMenuItem item, Color color) {
      Widget build([Widget? leading]) => MeCategoryRow(
        icon: item.icon,
        color: color,
        label: item.label,
        leading: leading,
        dimmed: item.id == MeItemId.becomeHost && !data.isPersonalInfoComplete,
        onTap: () => tap(item),
      );

      final Widget child = switch (item.id) {
        MeItemId.becomeHost when promo => MeHostUnlockRow(
          rowBuilder: build,
          onDismiss: markSeen,
        ),
        MeItemId.verification when badgeKey != null => MeFloatingPill(
          pill: MeBadgeLabel(labelKey: badgeKey, size: 9),
          child: build(),
        ),
        _ => build(),
      };
      return Padding(
        padding: EdgeInsets.only(bottom: 12.ms),
        child: child,
      );
    }

    final gap = SizedBox(height: 12.ms);
    return SliverList.list(
      children: [
        SizedBox(height: 16.ms),
        MeSettingsCard(
          icon: LucideIcons.wallet,
          color: BrandColors.lime,
          title: 'client:me.wallet.title',
          subtitle: 'client:me.wallet.subtitle',
          onTap: () => MeActions.open(context, AppRoutes.wallet),
        ),
        gap,
        const MeCategoryHeader(label: 'client:me.categories.identity'),
        for (final item in MeMenu.identity)
          if (item.visibleFor(isExpert: data.isExpert)) row(item, p.accent),
        if (data.isExpert) ...[
          gap,
          MeCategoryHeader(
            label: 'client:me.categories.hub',
            trailing: badgeKey == null
                ? null
                : MeBadgePromptChip(
                    labelKey: badgeKey,
                    onTap: () =>
                        MeActions.open(context, AppRoutes.verificationBadgeFee),
                  ),
          ),
          // RN HOST HUB, every option, as one card (lib/app/hosthub/hub).
          HostHubMenu(
            host: data.host!,
            open: (route) => MeActions.open(context, route),
            verificationRoute: data.verificationRoute,
            verificationPrompt: badgeKey == null
                ? null
                : MeBadgePromptChip(
                    labelKey: badgeKey,
                    onTap: () =>
                        MeActions.open(context, data.verificationRoute),
                  ),
          ),
        ],
        gap,
        MeSettingsCard(
          icon: LucideIcons.settings2,
          color: MeColors.resources,
          title: 'client:me.categories.resources',
          subtitle: 'client:me.categories.resources_hint',
          onTap: () => MeActions.open(context, MeMenu.resourcesRoute),
        ),
      ],
    );
  }
}
