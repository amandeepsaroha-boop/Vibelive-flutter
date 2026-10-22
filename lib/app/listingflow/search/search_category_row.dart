import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/search_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/search_format.dart';

/// A category hit, or a "category in location" hit. Tapping it searches for
/// the category (there is no category screen).
class SearchCategoryRow extends StatelessWidget {
  const SearchCategoryRow.category({
    super.key,
    required SearchCategory this.category,
    required this.onSearch,
  }) : location = null;

  const SearchCategoryRow.location({
    super.key,
    required SearchCategoryLocation this.location,
    required this.onSearch,
  }) : category = null;

  final SearchCategory? category;
  final SearchCategoryLocation? location;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final cat = category;
    final loc = location;
    final calls = cat?.callsCount;

    final String title;
    if (cat != null) {
      title = cat.name;
    } else if (loc!.label.isNotEmpty) {
      title = loc.label;
    } else {
      title = tVerbatim(context, 'search:results.category_in_location', {
        'category': loc.categoryName,
        'location': loc.locationName,
      });
    }

    return Pressable(
      activeOpacity: 0.85,
      onPressed: () => onSearch(cat?.name ?? loc!.query),
      child: Container(
        margin: EdgeInsets.only(bottom: 10.ms),
        padding: EdgeInsets.all(12.ms),
        decoration: BoxDecoration(
          color: dark ? AppColors.whiteA(0.04) : AppColors.white,
          borderRadius: BorderRadius.circular(18.ms),
          border: Border.all(
            color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.07),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40.ms,
              height: 40.ms,
              decoration: BoxDecoration(
                color: c.accentA(0.12),
                borderRadius: BorderRadius.circular(14.ms),
              ),
              child: Icon(
                cat != null ? LucideIcons.tag : LucideIcons.mapPin,
                size: 18.ms,
                color: c.accent,
              ),
            ),
            SizedBox(width: 12.ms),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  CText.raw(
                    title,
                    size: 14,
                    weight: FontWeight.w800,
                    maxLines: cat != null ? 1 : 2,
                  ),
                  if (calls != null)
                    Padding(
                      padding: EdgeInsets.only(top: 2.ms),
                      child: CText(
                        'search:results.calls_count',
                        count: calls,
                        size: 11,
                        weight: FontWeight.w600,
                        color: dark
                            ? AppColors.whiteA(0.45)
                            : AppColors.blackA(0.4),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 8.ms),
            Icon(
              LucideIcons.chevronRight,
              size: 18.ms,
              color: dark ? AppColors.whiteA(0.3) : AppColors.blackA(0.25),
            ),
          ],
        ),
      ),
    );
  }
}
