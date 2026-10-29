import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics_identity.dart';
import '../../../core/analytics/events/me_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../api/authscreen/auth_queries.dart';
import '../../api/client/client_models.dart';
import '../../api/hosthub/eligibility.dart';
import '../../api/hosthub/verification_models.dart';
import '../../authscreen/helper/link_parser.dart';
import '../../component/app_share.dart';
import '../../component/c_alert.dart';
import '../../component/c_toast.dart';
import 'resource_menu.dart';

/// What a category-menu row does (RN `CategoryMenuItems.handleAction`).
abstract final class ResourceMenuActions {
  /// [menu]: the category menu id, for analytics.
  static Future<void> run(
    BuildContext context,
    ResourceItem item, {
    String? menu,
  }) async {
    ResourceEvents.menuItemTapped(
      item: item.id,
      action: _actionName(item.action),
      menu: menu,
    );
    switch (item.action) {
      case ResourceAction.route:
        final route = _routeOf(item);
        if (route != null && await _allowed(context, item)) {
          if (context.mounted) await context.push<void>(route);
        }
      case ResourceAction.share:
        await _share(context);
      case ResourceAction.logout:
        MeEvents.logoutTapped(source: 'resources');
        final ok = await CAlert.confirm(
          title: 'resources:logout.title',
          message: 'resources:logout.message',
          confirmLabel: 'resources:logout.confirm',
          variant: CAlertVariant.error,
        );
        if (ok) {
          MeEvents.logoutConfirmed(source: 'resources');
          await logout();
        } else {
          MeEvents.logoutCancelled(source: 'resources');
        }
      case ResourceAction.deleteAccount:
        MeEvents.deleteAccountTapped();
        // RN signs out; the account is scheduled for deletion server-side.
        final ok = await CAlert.confirm(
          title: 'resources:delete.title',
          message: 'resources:delete.message',
          confirmLabel: 'resources:delete.confirm',
          variant: CAlertVariant.error,
        );
        if (ok) {
          MeEvents.deleteAccountConfirmed();
          AnalyticsIdentity.markSignOut('account_deleted');
          await logout();
        } else {
          MeEvents.deleteAccountCancelled();
        }
      case ResourceAction.dropdown:
        break; // the screen toggles it
    }
  }

  static String _actionName(ResourceAction a) => switch (a) {
    ResourceAction.route => 'route',
    ResourceAction.share => 'share',
    ResourceAction.dropdown => 'dropdown',
    ResourceAction.logout => 'logout',
    ResourceAction.deleteAccount => 'delete_account',
  };

  static String? _routeOf(ResourceItem item) {
    if (item.id != 'verification') return item.route;
    // Applied hosts see their status, everyone else starts at the fee.
    final step = HostEligibility.badgeStep(SessionStore.instance.value.expert);
    return switch (step) {
      VerificationStep.review ||
      VerificationStep.success => AppRoutes.verificationBadge,
      _ => AppRoutes.verificationBadgeFee,
    };
  }

  /// "Become a Host" waits for complete Personal Info (RN explains what is
  /// missing and offers to fill it in).
  static Future<bool> _allowed(BuildContext context, ResourceItem item) async {
    if (item.id != 'become-host') return true;
    final user = SessionStore.instance.value.user ?? const {};
    final missing = HostEligibility.missingPersonalInfo(user);
    MeEvents.becomeHostTapped(
      source: 'resources',
      eligible: missing.isEmpty,
      missingCount: missing.length,
    );
    if (missing.isEmpty) return true;
    final fields = missing.map((f) => context.t(f.i18nKey)).join(', ');
    final go = await CAlert.confirm(
      title: 'client:me.become_host_locked.title',
      message: 'client:me.become_host_locked.message',
      variables: {'fields': fields},
      confirmLabel: 'client:me.become_host_locked.action',
      variant: CAlertVariant.info,
    );
    MeEvents.becomeHostLocked(action: go ? 'fill_info' : 'cancel');
    if (go && context.mounted) {
      await context.push<void>(AppRoutes.personalInfo);
    }
    return false;
  }

  static Future<void> _share(BuildContext context) async {
    final s = SessionStore.instance.value;
    final profile = UserWithExpert(user: s.user ?? const {}, expert: s.expert);
    final slug = profile.shareSlug;
    if (slug == null) {
      MeEvents.profileShareUnavailable(source: 'resources');
      CToast.show('client:me.share.unavailable', variant: CToastVariant.error);
      return;
    }
    MeEvents.profileShared(source: 'resources', hostId: s.expertDocumentId);
    final link = LinkParser.shareLink(slug);
    await AppShare.text(
      context.t('client:me.share.message', variables: {'link': link}),
      contentType: 'own_profile',
    );
  }
}
