import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/router/app_router.dart';

/// Row ids with behaviour beyond "open the route".
enum MeItemId { route, share, becomeHost, verification }

/// One option of a profile-menu category (RN `menu-data.js`).
class MeMenuItem {
  const MeMenuItem(
    this.id,
    this.icon,
    this.label, {
    this.route,
    this.expertOnly = false,
    this.clientOnly = false,
  });

  final MeItemId id;
  final IconData icon;

  /// i18n key.
  final String label;
  final String? route;
  final bool expertOnly;
  final bool clientOnly;

  bool visibleFor({required bool isExpert}) =>
      !(expertOnly && !isExpert) && !(clientOnly && isExpert);
}

/// The categories the ME tab lists inline. RESOURCES is a card that opens
/// its own sub-menu (with the CMS pages, privacy and logout).
abstract final class MeMenu {
  static const identity = [
    MeMenuItem(
      MeItemId.share,
      LucideIcons.share2,
      'client:me.items.share',
      expertOnly: true,
    ),
    MeMenuItem(
      MeItemId.route,
      LucideIcons.qrCode,
      'client:me.items.qr',
      route: AppRoutes.profileQr,
      expertOnly: true,
    ),
    MeMenuItem(
      MeItemId.route,
      LucideIcons.settings,
      'client:me.items.personal',
      route: AppRoutes.personalInfo,
    ),
    MeMenuItem(
      MeItemId.becomeHost,
      LucideIcons.briefcase,
      'client:me.items.become_host',
      route: AppRoutes.hostOnboarding,
      clientOnly: true,
    ),
  ];

  /// Host Hub (hosts only).
  static const hub = [
    MeMenuItem(
      MeItemId.route,
      LucideIcons.briefcase,
      'client:me.items.pro_details',
      route: AppRoutes.professionalDetails,
    ),
    MeMenuItem(
      MeItemId.route,
      LucideIcons.star,
      'client:me.items.expertise',
      route: AppRoutes.expertise,
    ),
    MeMenuItem(
      MeItemId.route,
      LucideIcons.activity,
      'client:me.items.schedule',
      route: AppRoutes.schedule,
    ),
    MeMenuItem(
      MeItemId.route,
      LucideIcons.trendingUp,
      'client:me.items.rates',
      route: AppRoutes.callRates,
    ),
    MeMenuItem(
      MeItemId.route,
      LucideIcons.circleCheck,
      'client:me.items.approval',
      route: AppRoutes.approval,
    ),
    // Route depends on the badge step (MeData.verificationRoute).
    MeMenuItem(
      MeItemId.verification,
      LucideIcons.award,
      'client:me.items.verification',
    ),
  ];

  static const resourcesRoute = '${AppRoutes.categoryMenu}?id=resources';
}
