import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../api/resourcesscreen/resources_models.dart';
import 'resource_palette.dart';

/// What a row does beyond opening [ResourceItem.route].
enum ResourceAction { route, share, dropdown, logout, deleteAccount }

/// One option of a profile-menu category (RN `menu-data.js`).
class ResourceItem {
  const ResourceItem(
    this.id,
    this.icon,
    this.label, {
    this.route,
    this.action = ResourceAction.route,
    this.children = const [],
    this.rawLabel = false,
    this.expertOnly = false,
    this.clientOnly = false,
  });

  final String id;
  final IconData icon;

  /// i18n key, or server text when [rawLabel].
  final String label;
  final bool rawLabel;
  final String? route;
  final ResourceAction action;

  /// Rows of a dropdown (Account Privacy).
  final List<ResourceItem> children;
  final bool expertOnly;
  final bool clientOnly;

  bool visibleFor({required bool isExpert}) =>
      !(expertOnly && !isExpert) && !(clientOnly && isExpert);

  /// Delete Account is drawn in red.
  bool get destructive => action == ResourceAction.deleteAccount;
}

/// A category of the profile menu: `/me/category-menu?id=<id>`.
class ResourceCategory {
  const ResourceCategory(this.id, this.label, this.color, this.items);

  final String id;

  /// i18n key.
  final String label;

  /// Null = the theme accent (RN `brand.rose`).
  final Color? color;
  final List<ResourceItem> items;
}

/// RN `CATEGORIES` (menu-data.js) plus the CMS pages
/// (`CategoryMenuScreen`): pages go right before Logout.
abstract final class ResourceMenu {
  static const resourcesId = 'resources';

  static const _resources = <ResourceItem>[
    ResourceItem(
      'gst',
      LucideIcons.fileText,
      'resources:menu.items.gst',
      route: AppRoutes.gstDetails,
    ),
    ResourceItem(
      'referral',
      LucideIcons.gift,
      'resources:menu.items.referral',
      route: AppRoutes.referral,
    ),
    ResourceItem(
      'favourites',
      LucideIcons.heart,
      'resources:menu.items.favourites',
      route: AppRoutes.favourites,
    ),
    ResourceItem(
      'about',
      LucideIcons.info,
      'resources:menu.items.about',
      route: AppRoutes.aboutApp,
    ),
    ResourceItem(
      'support',
      LucideIcons.lifeBuoy,
      'resources:menu.items.support',
      route: AppRoutes.support,
    ),
    ResourceItem(
      'account-privacy',
      LucideIcons.shield,
      'resources:menu.items.privacy',
      action: ResourceAction.dropdown,
      children: [
        ResourceItem(
          'blocked-users',
          LucideIcons.userX,
          'resources:menu.items.blocked',
          route: AppRoutes.blockedUsers,
        ),
        ResourceItem(
          'delete-account',
          LucideIcons.trash2,
          'resources:menu.items.delete',
          action: ResourceAction.deleteAccount,
        ),
      ],
    ),
    ResourceItem(
      'logout',
      LucideIcons.logOut,
      'resources:menu.items.logout',
      action: ResourceAction.logout,
    ),
  ];

  static const _identity = <ResourceItem>[
    ResourceItem(
      'share',
      LucideIcons.share2,
      'client:me.items.share',
      action: ResourceAction.share,
      expertOnly: true,
    ),
    ResourceItem(
      'qr',
      LucideIcons.qrCode,
      'client:me.items.qr',
      route: AppRoutes.profileQr,
      expertOnly: true,
    ),
    ResourceItem(
      'personal',
      LucideIcons.settings,
      'client:me.items.personal',
      route: AppRoutes.personalInfo,
    ),
    ResourceItem(
      'become-host',
      LucideIcons.briefcase,
      'client:me.items.become_host',
      route: AppRoutes.hostOnboarding,
      clientOnly: true,
    ),
  ];

  static const _hub = <ResourceItem>[
    ResourceItem(
      'pro-details',
      LucideIcons.briefcase,
      'client:me.items.pro_details',
      route: AppRoutes.professionalDetails,
    ),
    ResourceItem(
      'expertise',
      LucideIcons.star,
      'client:me.items.expertise',
      route: AppRoutes.expertise,
    ),
    ResourceItem(
      'schedule',
      LucideIcons.activity,
      'client:me.items.schedule',
      route: AppRoutes.schedule,
    ),
    ResourceItem(
      'rates',
      LucideIcons.trendingUp,
      'client:me.items.rates',
      route: AppRoutes.callRates,
    ),
    ResourceItem(
      'approval',
      LucideIcons.circleCheck,
      'client:me.items.approval',
      route: AppRoutes.approval,
    ),
    ResourceItem(
      'verification',
      LucideIcons.award,
      'client:me.items.verification',
      route: AppRoutes.verificationBadgeFee,
    ),
  ];

  /// Null for an unknown id. Like RN, HOST HUB itself is not hidden from
  /// clients here (only the ME tab hides it).
  static ResourceCategory? category(
    String? id, {
    required bool isExpert,
    List<MenuPage> pages = const [],
  }) {
    final cat = switch (id) {
      resourcesId => ResourceCategory(
        resourcesId,
        'resources:menu.categories.resources',
        ResourcePalette.resources,
        withPages(pages),
      ),
      'identity' => const ResourceCategory(
        'identity',
        'resources:menu.categories.identity',
        null,
        _identity,
      ),
      'hub' => const ResourceCategory(
        'hub',
        'resources:menu.categories.hub',
        BrandColors.tealDarkest,
        _hub,
      ),
      _ => null,
    };
    if (cat == null) return null;
    return ResourceCategory(cat.id, cat.label, cat.color, [
      for (final item in cat.items)
        if (item.visibleFor(isExpert: isExpert)) item,
    ]);
  }

  /// Resources rows with the CMS pages inserted before Logout.
  static List<ResourceItem> withPages(List<MenuPage> pages) {
    final dynamicItems = [for (final p in pages) pageItem(p)];
    final logout = _resources.indexWhere(
      (i) => i.action == ResourceAction.logout,
    );
    return [
      ..._resources.take(logout),
      ...dynamicItems,
      ..._resources.skip(logout),
    ];
  }

  static ResourceItem pageItem(MenuPage page) => ResourceItem(
    'dynamic-${page.slug}',
    LucideIcons.fileText,
    page.title.isEmpty ? 'resources:page.untitled' : page.title,
    rawLabel: page.title.isNotEmpty,
    route: pageRoute(page.slug, page.title),
  );

  /// `/me/dynamic-page?slug=…&title=…`.
  static String pageRoute(String slug, [String title = '']) => Uri(
    path: AppRoutes.dynamicPage,
    queryParameters: {'slug': slug, if (title.isNotEmpty) 'title': title},
  ).toString();
}
