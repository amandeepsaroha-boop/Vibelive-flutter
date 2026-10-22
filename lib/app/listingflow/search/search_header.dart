import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/filter_models.dart';
import '../../component/c_back_button.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/search_controller.dart';

/// RN `SearchHeader`: back · search field with clear · filter with count.
/// Typing rebuilds only the field and its clear button.
class SearchHeader extends StatelessWidget {
  const SearchHeader({
    super.key,
    required this.controller,
    required this.onBack,
    required this.onOpenFilter,
  });

  final SearchScreenController controller;
  final VoidCallback onBack;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 8.ms, 16.ms, 12.ms),
      child: Row(
        children: [
          // RN SearchHeader: 44 square, radius 14, 20 chevron.
          CBackButton(onPressed: onBack, size: 20, boxSize: 44, radius: 14),
          SizedBox(width: 10.ms),
          Expanded(child: _SearchField(controller)),
          SizedBox(width: 10.ms),
          ValueListenableBuilder<HostFilter>(
            valueListenable: controller.filter,
            builder: (_, filter, _) =>
                _FilterButton(count: filter.count, onPressed: onOpenFilter),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField(this.controller);
  final SearchScreenController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final muted = dark ? AppColors.whiteA(0.5) : AppColors.blackA(0.45);
    return MediaQuery.withNoTextScaling(
      child: Container(
        height: 48.ms,
        padding: EdgeInsets.only(left: 14.ms, right: 6.ms),
        decoration: BoxDecoration(
          color: dark ? AppColors.whiteA(0.05) : AppColors.blackA(0.04),
          borderRadius: BorderRadius.circular(16.ms),
          border: Border.all(
            color: dark ? AppColors.whiteA(0.12) : AppColors.blackA(0.09),
          ),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 18.ms, color: muted),
            SizedBox(width: 8.ms),
            Expanded(
              child: TextField(
                controller: controller.text,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: controller.onChanged,
                onSubmitted: (_) => controller.submit(),
                cursorColor: c.accent,
                style: TextStyle(color: c.text, fontSize: 15.ms),
                decoration: InputDecoration(
                  // No label to float: no relayout animation on focus.
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: context.t('search:header.placeholder'),
                  hintStyle: TextStyle(
                    color: dark
                        ? AppColors.whiteA(0.4)
                        : AppColors.blackA(0.35),
                    fontSize: 15.ms,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller.text,
              builder: (_, value, _) => value.text.isEmpty
                  ? SizedBox(width: 8.ms)
                  : Pressable(
                      onPressed: controller.clear,
                      semanticLabel: context.t('search:header.clear'),
                      child: Padding(
                        padding: EdgeInsets.all(8.ms),
                        child: Icon(LucideIcons.x, size: 18.ms, color: muted),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded filter button; accent border, fill and count badge when active.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = count > 0;
    final idleBorder = c.isDark
        ? AppColors.whiteA(0.12)
        : AppColors.blackA(0.09);
    final idleBg = c.isDark ? AppColors.whiteA(0.05) : AppColors.blackA(0.04);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Pressable(
          onPressed: onPressed,
          semanticLabel: context.t('search:header.filter'),
          child: Container(
            width: 44.ms,
            height: 44.ms,
            decoration: BoxDecoration(
              color: active ? c.accentA(0.12) : idleBg,
              borderRadius: BorderRadius.circular(14.ms),
              border: Border.all(color: active ? c.accent : idleBorder),
            ),
            child: Icon(
              LucideIcons.slidersHorizontal,
              size: 18.ms,
              color: active ? c.accent : c.text,
            ),
          ),
        ),
        if (active)
          Positioned(
            top: -4.ms,
            right: -4.ms,
            child: IgnorePointer(
              child: Container(
                width: 16.ms,
                height: 16.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
                child: CText.raw(
                  '$count',
                  size: 9,
                  weight: FontWeight.w900,
                  color: c.onAccent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
