import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/filter_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';

/// One section of the filter sheet (RN `FilterSection`): title with the
/// selected count, "Reset", then a horizontal strip of chips starting with
/// "All". [selected] holds one value for a single-choice section.
class FilterSection extends StatelessWidget {
  const FilterSection({
    super.key,
    required this.titleKey,
    required this.allKey,
    required this.options,
    required this.selected,
    required this.onToggle,
    required this.onReset,
    this.multi = false,
    this.loading = false,
    this.emptyKey,
    this.onRetry,
  });

  final String titleKey;
  final String allKey;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onReset;
  final bool multi;

  /// Options still loading: skeleton chips.
  final bool loading;

  /// Shown when there is nothing to offer (null = hide the strip).
  final String? emptyKey;

  /// Adds "Retry" after [emptyKey] (the options failed to load).
  final VoidCallback? onRetry;

  bool _isSelected(String option) => selected.any((s) => sameText(s, option));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final any = selected.isNotEmpty;
    final muted = c.isDark ? AppColors.whiteA(0.35) : AppColors.blackA(0.3);

    final Widget strip;
    if (options.isEmpty && loading) {
      strip = const _SkeletonChips();
    } else if (options.isEmpty) {
      strip = Row(
        children: [
          Flexible(
            child: CText(
              emptyKey ?? 'states.empty_title',
              size: 12,
              weight: FontWeight.w600,
              color: muted,
              maxLines: 2,
            ),
          ),
          if (onRetry != null)
            Pressable(
              onPressed: onRetry,
              hitPadding: EdgeInsets.all(8.ms),
              child: CText(
                'actions.retry',
                size: 12,
                weight: FontWeight.w800,
                color: c.accent,
              ),
            ),
        ],
      );
    } else {
      strip = SizedBox(
        height: 40.ms,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(vertical: 3.ms),
          itemCount: options.length + 1,
          separatorBuilder: (_, _) => SizedBox(width: 8.ms),
          itemBuilder: (_, i) => i == 0
              ? _Chip(
                  label: allKey,
                  translate: true,
                  active: !any,
                  onPressed: onReset,
                )
              : _Chip(
                  label: options[i - 1],
                  active: _isSelected(options[i - 1]),
                  onPressed: () => onToggle(options[i - 1]),
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10.ms),
          child: Row(
            children: [
              Flexible(
                child: CText(
                  titleKey,
                  size: 13,
                  weight: FontWeight.w900,
                  letterSpacing: 0.8,
                  uppercase: true,
                  color: c.text.withValues(alpha: 0.6),
                  maxLines: 1,
                ),
              ),
              if (multi && any)
                CText.raw(
                  ' (${selected.length})',
                  size: 12,
                  weight: FontWeight.w800,
                  color: c.accent,
                ),
              const Spacer(),
              if (any)
                Pressable(
                  onPressed: onReset,
                  hitPadding: EdgeInsets.all(8.ms),
                  child: CText(
                    'search:filter.reset',
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
            ],
          ),
        ),
        strip,
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.active,
    required this.onPressed,
    this.translate = false,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;
  final bool translate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final fg = active
        ? c.accent
        : (dark ? AppColors.whiteA(0.75) : AppColors.blackA(0.65));
    final weight = active ? FontWeight.w900 : FontWeight.w700;
    return Pressable(
      onPressed: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(horizontal: 16.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? c.accentA(0.12)
              : (dark ? AppColors.whiteA(0.04) : AppColors.blackA(0.03)),
          borderRadius: BorderRadius.circular(20.ms),
          border: Border.all(
            width: 1.5,
            color: active
                ? c.accent
                : (dark ? AppColors.whiteA(0.14) : AppColors.blackA(0.1)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (active) ...[
              Icon(
                LucideIcons.check,
                size: 12.ms,
                color: c.accent,
                weight: 900,
              ),
              SizedBox(width: 6.ms),
            ],
            translate
                ? CText(label, size: 12.5, weight: weight, color: fg)
                : CText.raw(label, size: 12.5, weight: weight, color: fg),
          ],
        ),
      ),
    );
  }
}

class _SkeletonChips extends StatelessWidget {
  const _SkeletonChips();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40.ms,
      child: ClipRect(
        child: Shimmer(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final w in const [110, 80, 95, 70, 90])
                  Padding(
                    padding: EdgeInsets.only(right: 8.ms),
                    child: SkeletonBox(width: w.ms, height: 34.ms, radius: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
