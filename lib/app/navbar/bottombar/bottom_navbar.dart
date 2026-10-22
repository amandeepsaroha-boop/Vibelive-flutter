import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/pressable.dart';
import '../../homescreen/helper/home_controller.dart';
import 'navbar_collapse.dart';

/// Floating pill: Discover · History · Me (RN `BottomNavbar`). Solid, not
/// blurred: a live blur re-renders on every scroll frame. Shrinks while the
/// feed scrolls down.
///
/// Home's `Scaffold.bottomNavigationBar` (with `extendBody`), so floating
/// toasts land above it. The margins around the pill let taps through.
class BottomNavbar extends StatelessWidget {
  const BottomNavbar({super.key, required this.home});
  final HomeController home;

  /// Pill height (RN: 64 scaled, at least 66).
  static double get barHeight => math.max(64.ms, 66);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // viewPadding: the bar must not jump when a keyboard (in a sheet on top)
    // eats the bottom padding.
    final bottom = math.max(
      12.ms,
      MediaQuery.viewPaddingOf(context).bottom + 8.ms,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(52.ms, 0, 52.ms, bottom),
      // Collapsing moves and scales one cached layer (the inner boundary)
      // inside its own (the outer one): the Home page isn't repainted.
      child: RepaintBoundary(
        child: ValueListenableBuilder<bool>(
          valueListenable: NavbarCollapse.instance,
          builder: (_, collapsed, bar) => AnimatedSlide(
            offset: Offset(0, collapsed ? 0.12 : 0),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: collapsed ? 0.75 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: bar,
            ),
          ),
          child: RepaintBoundary(
            child: Container(
              height: barHeight,
              padding: EdgeInsets.symmetric(horizontal: 8.ms),
              decoration: BoxDecoration(
                color: c.navBg,
                borderRadius: BorderRadius.circular(26.ms),
                border: Border.all(width: 1.5, color: c.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.blackA(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ValueListenableBuilder<HomeTab>(
                valueListenable: home.tab,
                builder: (_, active, _) => Row(
                  children: [
                    for (final (tab, icon) in const [
                      (HomeTab.discover, LucideIcons.compass),
                      (HomeTab.history, LucideIcons.activity),
                      (HomeTab.me, LucideIcons.user),
                    ])
                      Expanded(
                        child: _Item(
                          icon: icon,
                          label: 'home:nav.${tab.name}',
                          active: active == tab,
                          onPressed: () => home.select(tab),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onPressed,
      activeOpacity: 0.8,
      semanticLabel: context.t(label),
      child: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1 : 0.9,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: active ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 44.ms,
                  height: 44.ms,
                  decoration: BoxDecoration(
                    color: AppColors.navActiveBg,
                    borderRadius: BorderRadius.circular(17.ms),
                  ),
                ),
              ),
            ),
            Icon(
              icon,
              size: 21.ms,
              color: active ? c.accent : AppColors.gray,
              weight: active ? 700 : 500,
            ),
          ],
        ),
      ),
    );
  }
}
