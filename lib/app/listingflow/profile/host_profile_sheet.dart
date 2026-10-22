import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/callscreen/call_queries.dart';
import '../../api/client/block_api.dart';
import '../../api/client/client_queries.dart';
import '../../api/listingflow/listing_models.dart';
import '../../api/listingflow/listing_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/qr_code_sheet.dart';
import 'helper/call_start.dart';
import 'helper/host_profile_controller.dart';
import 'helper/host_profile_rules.dart';
import 'profile_about.dart';
import 'profile_call_actions.dart';
import 'profile_gallery.dart';
import 'profile_header.dart';
import 'profile_reviews.dart';
import 'profile_sheets.dart';
import 'profile_skeleton.dart';
import 'report_sheet.dart';
import 'safety_prompt.dart';

/// Opens a host's profile (RN `ProfileModal`): a full-height sheet, dragged
/// down (or flung) to close. Opens in the same frame, never after a request:
/// [host] renders at once (upgraded from the session's host index when it
/// is a summary); only what a summary lacks loads, behind section skeletons.
Future<void> showHostProfile(BuildContext context, HostCard host) {
  // Reviews start now, in parallel with the sheet (and any detail read).
  prefetchExpertReviews(host.expertProfileDocumentId);
  final navigator = Navigator.of(context, rootNavigator: true);
  // The sheet drops the top padding: read the status bar height above it.
  final topInset = MediaQuery.paddingOf(navigator.context).top;
  // Our own route object, so the sheet can close itself without depending
  // on `ModalRoute.of` (which rebuilds it whenever a dialog opens on top).
  late final ModalBottomSheetRoute<void> route;
  // One instance: the route rebuilds its page on every MediaQuery change
  // (the keyboard of a sheet opened on top), the same widget skips that.
  late final sheet = _HostProfileSheet(
    host: host,
    origin: context,
    route: route,
    topInset: topInset,
  );
  route = ModalBottomSheetRoute<void>(
    builder: (_) => sheet,
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    elevation: 0,
    modalBarrierColor: context.colors.modalBackdrop,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 320),
      reverseDuration: Duration(milliseconds: 220),
    ),
  );
  return navigator.push(route);
}

/// Pulling the list down at its top shrinks the sheet; released below
/// 70 % (or flung) it snaps to [_closeAt] and the sheet closes. The content
/// keeps its full height while dragging, so a drag only moves it (no
/// relayout).
class _HostProfileSheet extends StatelessWidget {
  const _HostProfileSheet({
    required this.host,
    required this.origin,
    required this.route,
    required this.topInset,
  });

  final HostCard host;
  final BuildContext origin;
  final ModalRoute<void> route;
  final double topInset;

  static const _closeAt = 0.4;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1,
      minChildSize: _closeAt,
      snap: true,
      builder: (_, scroll) => OverflowBox(
        alignment: Alignment.topCenter,
        minHeight: box.maxHeight,
        maxHeight: box.maxHeight,
        child: _ProfileView(
          host: host,
          origin: origin,
          route: route,
          scroll: scroll,
          topInset: topInset,
        ),
      ),
    ),
  );
}

class _ProfileView extends HookWidget {
  const _ProfileView({
    required this.host,
    required this.origin,
    required this.route,
    required this.scroll,
    required this.topInset,
  });

  final HostCard host;

  /// Where the profile was opened from: outlives the sheet (call hand-off).
  final BuildContext origin;

  /// This sheet's route.
  final ModalRoute<void> route;
  final ScrollController scroll;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final session = useValueListenable(SessionStore.instance);

    // Summary cards (no rates / service areas) get the full profile: from
    // the host index at once, else fetched behind section skeletons.
    final detail = useHostSheetDetail(context, host);
    final profile = detail.profile;
    final waiting = detail.waiting;
    final failed = detail.error;

    final isMe = useMemoized(() => HostProfileRules.isMe(profile, session), [
      profile,
      session,
    ]);
    final isCompany = HostProfileRules.isCompanyUser(session.user);
    // Known expert id: reviews load in parallel with the profile.
    final reviewsKey =
        profile.expertProfileDocumentId ??
        (waiting ? null : HostProfileRules.expertKey(profile));
    final reviews = useExpertReviews(
      context,
      reviewsKey,
      enabled: reviewsKey != null,
    );

    final router = GoRouter.maybeOf(context);
    final controller = useMemoized(
      () => HostProfileController(
        close: () => _close(route),
        navigate: (path) {
          if (router != null) unawaited(router.push(path));
        },
        confirmStart: (video) => showSafetyPrompt(context, video: video),
        handOff: (target, video) {
          final ctx = origin.mounted ? origin : rootNavigatorKey.currentContext;
          return ctx == null
              ? Future.value()
              : startOutgoingCall(ctx, host: target, video: video);
        },
      ),
    );
    useEffect(() => controller.dispose, [controller]);

    final block = useBlockUser(
      onSuccess: () {
        controller.close();
        CAlert.show(
          title: 'host:block.success_title',
          message: 'host:block.success',
          variant: CAlertVariant.success,
        );
      },
      onError: (e) => CAlert.error(e, title: 'host:block.failed_title'),
    );

    Future<void> openMenu() async {
      final action = await showProfileMenu(context);
      if (action == null || !context.mounted) return;
      switch (action) {
        case ProfileMenuAction.report:
          await showReportSheet(context, host: profile);
        case ProfileMenuAction.block:
          final target = HostProfileRules.blockTarget(profile);
          if (target == null) {
            await CAlert.show(
              title: 'errors.title',
              message: 'host:block.missing',
              variant: CAlertVariant.error,
            );
            return;
          }
          final confirmed = await CAlert.confirm(
            title: 'host:block.title',
            message: 'host:block.message',
            confirmLabel: 'host:block.confirm',
            variant: CAlertVariant.error,
          );
          if (confirmed && context.mounted) {
            await block.mutate(BlockUserInput(target));
          }
      }
    }

    final size = MediaQuery.sizeOf(context);
    final heroHeight = math.min((size.height * 0.48).roundToDouble(), 420.0);
    // Scroll offset where the card's background reaches the status bar.
    final pastHeroAt = heroHeight - 36.ms - topInset;

    final gallery = useMemoized(
      () => ProfileGallery(
        host: profile,
        height: heroHeight,
        topInset: topInset,
        controller: controller,
        canFavorite: session.isAuthenticated && !isMe,
      ),
      [profile, isMe, session.isAuthenticated, heroHeight, topInset],
    );
    // Built once per profile; the list builds each section lazily.
    final sections = useMemoized(
      () => <Widget>[
        ProfileHeader(
          host: profile,
          showCompany: isMe && isCompany,
          onInfluencer: () => showInfluencerSheet(context, profile),
        ),
        if (waiting)
          const ProfileBodySkeleton()
        else if (failed != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24.ms),
            child: CStateView.error(context, failed, onRetry: detail.retry),
          )
        else ...[
          ProfileCallActions(
            host: profile,
            controller: controller,
            isMe: isMe,
            isCompany: isCompany,
          ),
          ProfileSocialLinks(host: profile),
          ProfileVibeCard(host: profile),
          ProfileSpecializationCard(host: profile),
        ],
      ],
      [profile, isMe, isCompany, waiting, failed],
    );

    final list = NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) {
        if (n.depth == 0) controller.onScroll(n.metrics.pixels, pastHeroAt);
        return false;
      },
      child: CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(child: gallery),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20.ms),
            sliver: SliverList.list(children: sections),
          ),
          SliverToBoxAdapter(
            child: ProfileReviews(
              query: reviews,
              waiting: reviewsKey == null && waiting,
            ),
          ),
          const SliverToBoxAdapter(child: _ListEnd()),
        ],
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: controller.pastHero,
      builder: (_, past, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (past && !c.isDark
                    ? SystemUiOverlayStyle.dark
                    : SystemUiOverlayStyle.light)
                .copyWith(statusBarColor: AppColors.transparent),
        child: child!,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.ms)),
        child: ColoredBox(
          color: profileCardColor(c),
          child: Stack(
            children: [
              Positioned.fill(child: list),
              Positioned(
                top: topInset + 14.ms,
                left: 16.ms,
                right: 16.ms,
                child: ProfileTopBar(
                  onBack: controller.close,
                  onShare: () => showShareSheet(
                    context,
                    url: HostProfileRules.shareUrl(profile),
                    onShareVia: () => controller.share(context, profile),
                    onCopy: () => controller.copyLink(profile),
                    onShowQr: () => showQrCodeSheet(
                      context,
                      url: HostProfileRules.shareUrl(profile),
                      name: profile.name.isEmpty
                          ? context.t(HostCard.unknownNameKey)
                          : profile.name,
                      handle: profile.handler,
                    ),
                  ),
                  onMenu: isMe ? null : () => unawaited(openMenu()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pops this sheet, also when something else is above it.
  static void _close(ModalRoute<void> route) {
    final navigator = route.navigator;
    if (navigator == null || !route.isActive) return;
    route.isCurrent ? navigator.pop() : navigator.removeRoute(route);
  }
}

/// Room under the reviews: clears the home indicator. Reads the view
/// padding (fixed while a keyboard opens above) so only this box depends
/// on it.
class _ListEnd extends StatelessWidget {
  const _ListEnd();

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 64.ms + MediaQuery.viewPaddingOf(context).bottom);
}
