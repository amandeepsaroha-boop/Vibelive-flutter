import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/app_scope.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/strapi.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/filter_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../client/me/me_menu_sheet.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../homescreen/helper/home_controller.dart';
import '../../listingflow/filter/filter_sheet.dart';
import 'top_bar_button.dart';

/// Discover header: theme · search · filter on the left, wallet on the right
/// (RN DiscoveryScreen header).
class DiscoverTopBar extends StatelessWidget {
  const DiscoverTopBar({super.key, required this.home});
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = AppScope.of(context).theme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 10.ms),
      child: Row(
        children: [
          TopBarButton(
            icon: c.isDark ? LucideIcons.sun : LucideIcons.moon,
            color: c.accent,
            semanticLabel: context.t('home:header.theme'),
            onPressed: () => theme.toggle(context),
            onLongPress: () {
              theme.setMode(ThemeMode.system);
              CToast.show('home:header.theme_system');
            },
          ),
          SizedBox(width: 10.ms),
          TopBarButton(
            icon: LucideIcons.search,
            semanticLabel: context.t('home:header.search'),
            onPressed: () => context.push(AppRoutes.search),
          ),
          SizedBox(width: 10.ms),
          ValueListenableBuilder<HostFilter>(
            valueListenable: home.filter,
            builder: (_, filter, _) => TopBarButton(
              icon: LucideIcons.slidersHorizontal,
              color: filter.isActive ? c.accent : null,
              badge: filter.languages.length + (filter.hasTopic ? 1 : 0),
              semanticLabel: context.t('home:header.filter'),
              onPressed: () async {
                final next = await showFilterSheet(context, current: filter);
                if (next != null) home.filter.value = next;
              },
            ),
          ),
          SizedBox(width: 10.ms),
          const Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _WalletChip(),
            ),
          ),
        ],
      ),
    );
  }
}

/// "WALLET / Rs 120.0" + wallet button. Shimmer until the balance is known;
/// "Rs 0.0" when it can't be (RN). Refetched when Home is back on top (after
/// a call, a recharge…), like RN's focus effect.
class _WalletChip extends HookWidget {
  const _WalletChip();

  /// Closing a sheet also brings Home back on top: don't refetch for each.
  static const _minRefreshGap = Duration(seconds: 5);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wallet = useWalletBalance(context);
    final signedIn = SessionStore.instance.value.userDocumentId != null;
    final total =
        wallet.data?.totalBalance ?? (wallet.isError || !signedIn ? 0 : null);

    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    final lastRefresh = useRef(DateTime.now());
    useEffect(() {
      final now = DateTime.now();
      if (onTop && now.difference(lastRefresh.value) > _minRefreshGap) {
        lastRefresh.value = now;
        Future.microtask(invalidateWalletQueries); // not during build
      }
      return null;
    }, [onTop]);

    return Pressable(
      activeOpacity: 0.85,
      onPressed: () => context.push(AppRoutes.wallet),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CText(
                  'home:header.wallet',
                  size: 10,
                  weight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: c.text.withValues(alpha: 0.5),
                  maxLines: 1,
                ),
                SizedBox(height: 2.ms),
                if (total == null)
                  Shimmer(
                    child: SkeletonBox(width: 60.ms, height: 16.ms, radius: 4),
                  )
                else
                  // A large balance shrinks rather than being cut off.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: CText(
                      'home:header.amount',
                      variables: {'amount': total.toStringAsFixed(1)},
                      size: 14,
                      weight: FontWeight.w900,
                      color: c.text,
                      maxLines: 1,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 10.ms),
          Container(
            width: 44.ms,
            height: 44.ms,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(14.ms),
            ),
            child: Icon(LucideIcons.wallet, size: 18.ms, color: c.onAccent),
          ),
        ],
      ),
    );
  }
}

/// ME header: back to Discover, title, menu (RN DiscoveryScreen, view ME).
class MeTopBar extends StatelessWidget {
  const MeTopBar({super.key, required this.home});
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 10.ms),
      child: Row(
        children: [
          TopBarButton(
            icon: LucideIcons.chevronLeft,
            semanticLabel: context.t('actions.back'),
            onPressed: () => home.select(HomeTab.discover),
          ),
          Expanded(
            child: ValueListenableBuilder<SessionState>(
              valueListenable: SessionStore.instance,
              builder: (_, s, _) => CText(
                J.boolean(s.user?['is_company_account'])
                    ? 'home:me.company_title'
                    : 'home:me.title',
                size: 22,
                weight: FontWeight.w800,
                color: c.text,
                align: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ),
          TopBarButton(
            icon: LucideIcons.ellipsisVertical,
            semanticLabel: context.t('home:me.menu'),
            onPressed: () => showMeMenu(context),
          ),
        ],
      ),
    );
  }
}
