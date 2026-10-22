import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../helper/resource_menu.dart';
import '../helper/resource_palette.dart';

/// A row of the category menu (RN `CategoryMenuItems`). [child] rows are
/// the smaller ones under an open dropdown.
class ResourceRow extends StatelessWidget {
  const ResourceRow({
    super.key,
    required this.item,
    required this.color,
    required this.onTap,
    this.child = false,
    this.open = false,
  });

  final ResourceItem item;
  final Color color;
  final VoidCallback onTap;
  final bool child;

  /// Dropdown expanded: the chevron points down.
  final bool open;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    final tint = item.destructive ? AppColors.logoutRed : color;
    final box = child ? 32.0 : 40.0;
    final label = item.rawLabel
        ? CText.raw(
            item.label,
            size: child ? 14 : 15,
            weight: FontWeight.w800,
            color: item.destructive ? AppColors.logoutRed : p.text,
            maxLines: 1,
          )
        : CText(
            item.label,
            size: child ? 14 : 15,
            weight: FontWeight.w800,
            color: item.destructive ? AppColors.logoutRed : p.text,
            maxLines: 1,
          );
    return Pressable(
      onPressed: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16.ms,
          vertical: (child ? 14 : 18).ms,
        ),
        decoration: BoxDecoration(
          color: p.menuCard,
          borderRadius: BorderRadius.circular((child ? 18 : 22).ms),
          border: Border.all(color: p.menuBorder),
        ),
        child: Row(
          children: [
            Container(
              width: box.ms,
              height: box.ms,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withAlpha(0x15),
                borderRadius: BorderRadius.circular((child ? 10 : 12).ms),
              ),
              child: Icon(item.icon, size: (child ? 16 : 20).ms, color: tint),
            ),
            SizedBox(width: (child ? 12 : 16).ms),
            Expanded(child: label),
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                LucideIcons.chevronRight,
                size: (child ? 16 : 18).ms,
                color: p.menuMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A CMS-page row still loading.
class ResourceRowSkeleton extends StatelessWidget {
  const ResourceRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: SkeletonBox(height: 76.ms, radius: 22.ms),
  );
}
