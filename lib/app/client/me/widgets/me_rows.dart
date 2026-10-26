import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/me_palette.dart';

/// Rounded square with a tinted icon (every ME row and tile).
class MeIconBox extends StatelessWidget {
  const MeIconBox({
    super.key,
    required this.color,
    this.icon,
    this.child,
    required this.size,
    required this.radius,
    required this.iconSize,
    this.alpha = 0x22,
  });

  final Color color;
  final IconData? icon;

  /// Replaces [icon] (animated icons).
  final Widget? child;
  final double size;
  final double radius;
  final double iconSize;

  /// RN `color + '22'` style hex alpha.
  final int alpha;

  @override
  Widget build(BuildContext context) => Container(
    width: size.ms,
    height: size.ms,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color.withAlpha(alpha),
      borderRadius: BorderRadius.circular(radius.ms),
    ),
    child: child ?? Icon(icon, size: iconSize.ms, color: color),
  );
}

/// One 80pt card of the ME list (RN `SettingsCard`): icon, title, subtitle,
/// chevron.
class MeSettingsCard extends StatelessWidget {
  const MeSettingsCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.chevron = true,
  });

  final IconData icon;
  final Color color;

  /// i18n keys.
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    return Pressable(
      activeOpacity: 0.8,
      onPressed: onTap,
      child: Container(
        height: 80.ms,
        padding: EdgeInsets.symmetric(horizontal: 20.ms),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(28.ms),
          border: Border.all(color: p.cardBorder),
        ),
        child: Row(
          children: [
            MeIconBox(
              color: color,
              icon: icon,
              size: 48,
              radius: 16,
              iconSize: 22,
              alpha: 0x20,
            ),
            SizedBox(width: 16.ms),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CText(
                    title,
                    size: 16,
                    weight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: p.text,
                    maxLines: 1,
                  ),
                  SizedBox(height: 2.ms),
                  CText(
                    subtitle,
                    size: 11,
                    weight: FontWeight.w600,
                    color: p.muted,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (chevron)
              Icon(LucideIcons.chevronRight, size: 18.ms, color: p.text),
          ],
        ),
      ),
    );
  }
}

/// Category title above its rows, with an optional pill on the right.
class MeCategoryHeader extends StatelessWidget {
  const MeCategoryHeader({super.key, required this.label, this.trailing});

  /// i18n key.
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 8.ms, bottom: 10.ms),
    child: Row(
      children: [
        SizedBox(width: 6.ms),
        Expanded(
          child: CText(
            label,
            size: 11,
            weight: FontWeight.w900,
            letterSpacing: 2,
            color: MePalette.of(context).muted,
            maxLines: 1,
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Lime "✨ APPLY FOR BADGE" chip next to HOST HUB.
class MeBadgePromptChip extends StatelessWidget {
  const MeBadgePromptChip({
    super.key,
    required this.labelKey,
    required this.onTap,
  });

  final String labelKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    activeOpacity: 0.8,
    onPressed: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 5.ms),
      decoration: BoxDecoration(
        color: BrandColors.lime,
        borderRadius: BorderRadius.circular(999),
      ),
      child: MeBadgeLabel(labelKey: labelKey),
    ),
  );
}

/// "✨ {label}" in the badge chip / floating pill style.
class MeBadgeLabel extends StatelessWidget {
  const MeBadgeLabel({super.key, required this.labelKey, this.size = 10});

  final String labelKey;
  final double size;

  @override
  Widget build(BuildContext context) => CText(
    'client:me.badge_pill',
    variables: {'label': context.t(labelKey)},
    size: size,
    weight: FontWeight.w900,
    letterSpacing: 0.8,
    uppercase: true,
    color: AppColors.black,
    maxLines: 1,
  );
}
