import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/strapi.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/filter_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../client/me/me_menu_sheet.dart';
import '../../component/app_logo.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../homescreen/helper/home_controller.dart';
import '../../splashscreen/launch_logo.dart';
import '../../listingflow/filter/filter_sheet.dart';
import 'top_bar_button.dart';

/// Discover header (mockup): the wordmark, then search · filter · balance
/// pill (it opens the wallet). Availability is the host pill in the bottom dock; the
/// light / dark switch lives in Me → Settings.
class DiscoverTopBar extends StatelessWidget {
  const DiscoverTopBar({super.key, required this.home});
  final HomeController home;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void openWallet() {
      DiscoverEvents.topBarTapped(button: 'wallet', tab: 'discover');
      prefetchWalletTransactions();
      context.push(AppRoutes.wallet);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 12.ms, 16.ms, 12.ms),
      child: Row(
        children: [
          // A narrow phone shrinks the wordmark, never the controls.
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: LaunchLogoAnchor(
                  child: AppLogo(size: 126.ms, height: 126.ms * AppLogo.aspect),
                ),
              ),
            ),
          ),
          SizedBox(width: 6.ms),
          _RoundIcon(
            icon: LucideIcons.search,
            semanticLabel: context.t('home:header.search'),
            onPressed: () {
              DiscoverEvents.topBarTapped(button: 'search', tab: 'discover');
              context.push(AppRoutes.search);
            },
          ),
          ValueListenableBuilder<HostFilter>(
            valueListenable: home.filter,
            builder: (_, filter, _) => _RoundIcon(
              icon: LucideIcons.slidersHorizontal,
              color: filter.isActive ? c.accent : null,
              badge: filter.languages.length + (filter.hasTopic ? 1 : 0),
              semanticLabel: context.t('home:header.filter'),
              onPressed: () async {
                DiscoverEvents.topBarTapped(button: 'filter', tab: 'discover');
                final next = await showFilterSheet(context, current: filter);
                if (next != null) home.filter.value = next;
              },
            ),
          ),
          SizedBox(width: 4.ms),
          _WalletChip(onPressed: openWallet),
        ],
      ),
    );
  }
}

/// A plain round icon button of the Discover header, with a count badge.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.color,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final Color? color;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: SizedBox.square(
        dimension: 40.ms,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              size: 22.ms,
              color: color ?? c.text.withValues(alpha: 0.8),
            ),
            if (badge > 0)
              Positioned(
                top: 2.ms,
                right: 2.ms,
                child: Container(
                  width: 15.ms,
                  height: 15.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                  child: CText.raw(
                    '$badge',
                    size: 8.5,
                    weight: FontWeight.w900,
                    color: c.onAccent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Balance pill "₹ 246" / "₹ 10k" ([compactAmount]). Shimmer until the
/// balance is known; "₹ 0" when it can't be (RN). Refetched when Home is
/// back on top (after a call, a recharge…), like RN's focus effect.
class _WalletChip extends HookWidget {
  const _WalletChip({required this.onPressed});
  final VoidCallback onPressed;

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
      semanticLabel: context.t('home:header.wallet'),
      onPressed: onPressed,
      child: Container(
        height: 36.ms,
        constraints: BoxConstraints(maxWidth: 112.ms),
        padding: EdgeInsets.symmetric(horizontal: 12.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.isDark ? AppColors.whiteA(0.08) : const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: c.isDark ? AppColors.whiteA(0.14) : const Color(0xFFC7D2FE),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.wallet, size: 14.ms, color: c.accent),
            SizedBox(width: 6.ms),
            if (total == null)
              Shimmer(
                child: SkeletonBox(width: 34.ms, height: 12.ms, radius: 4),
              )
            else
              Flexible(
                child: FittedBox(
                  // Never cut off: a long balance shrinks instead.
                  fit: BoxFit.scaleDown,
                  child: CText(
                    'home:header.amount',
                    variables: {'amount': compactAmount(total)},
                    size: 13.5,
                    weight: FontWeight.w900,
                    color: c.text,
                    maxLines: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A balance for the header: whole rupees below 1,000 (`120`, `999.5`),
/// then thousands with one decimal, rounded down so it never shows more
/// than there is (`1.2k`, `10k`, `150k`).
String compactAmount(double value) {
  String trim(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (value < 1000) return trim((value * 10).floorToDouble() / 10);
  return '${trim((value / 100).floorToDouble() / 10)}k';
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
            onPressed: () {
              DiscoverEvents.topBarTapped(button: 'back', tab: 'me');
              home.select(HomeTab.discover);
            },
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
            onPressed: () {
              DiscoverEvents.topBarTapped(button: 'me_menu', tab: 'me');
              showMeMenu(context);
            },
          ),
        ],
      ),
    );
  }
}

/// HISTORY header, built like [MeTopBar]: back to Discover and the title,
/// centred (the right slot is kept empty so the title stays centred).
class HistoryTopBar extends StatelessWidget {
  const HistoryTopBar({super.key, required this.home});
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
            onPressed: () {
              DiscoverEvents.topBarTapped(button: 'back', tab: 'history');
              home.select(HomeTab.discover);
            },
          ),
          Expanded(
            child: CText(
              'home:history.title',
              size: 22,
              weight: FontWeight.w800,
              color: c.text,
              align: TextAlign.center,
              maxLines: 1,
            ),
          ),
          SizedBox(width: 44.ms),
        ],
      ),
    );
  }
}
