import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/catalog_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../helper/resource_palette.dart';

/// RN search box: 56 tall, magnifier, plain text field.
class CategorySearch extends StatelessWidget {
  const CategorySearch({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    return Container(
      height: 56.ms,
      padding: EdgeInsets.symmetric(horizontal: 12.ms),
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(14.ms),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 16.ms, color: p.muted),
          SizedBox(width: 10.ms),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                color: p.text,
                fontSize: 16.ms,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: p.text,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: context.t('resources:categories.search'),
                hintStyle: TextStyle(
                  color: p.muted,
                  fontSize: 16.ms,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One category; lime border and check when picked.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.option,
    required this.active,
    required this.onTap,
  });

  final HostOption option;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 8.ms),
      child: Pressable(
        onPressed: onTap,
        activeOpacity: 0.86,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 13.ms),
          decoration: BoxDecoration(
            color: active ? BrandColors.limeA(0.11) : p.card,
            borderRadius: BorderRadius.circular(14.ms),
            border: Border.all(color: active ? BrandColors.lime : p.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: CText.raw(
                  option.label,
                  size: 14,
                  weight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              if (active)
                Icon(LucideIcons.check, size: 16.ms, color: BrandColors.lime),
            ],
          ),
        ),
      ),
    );
  }
}

/// First load: hint, search box and rows.
class CategoriesSkeleton extends StatelessWidget {
  const CategoriesSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FractionallySizedBox(
          widthFactor: 0.7,
          child: SkeletonBox(height: 12.ms, radius: 6),
        ),
        SizedBox(height: 10.ms),
        SkeletonBox(height: 56.ms, radius: 14.ms),
        SizedBox(height: 12.ms),
        for (var i = 0; i < 8; i++) ...[
          SkeletonBox(height: 46.ms, radius: 14.ms),
          SizedBox(height: 8.ms),
        ],
      ],
    ),
  );
}
