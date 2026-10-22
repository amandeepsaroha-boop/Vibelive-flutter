import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_state_view.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/host_palette.dart';
import 'search_box.dart';

/// Searchable list for the pickers (state, district, languages): lazy rows,
/// a shimmer while loading, retry on error.
class HostOptionList<T> extends StatelessWidget {
  const HostOptionList({
    super.key,
    required this.items,
    required this.labelOf,
    required this.isSelected,
    required this.onTap,
    this.search,
    this.loading = false,
    this.error,
    this.onRetry,
    this.multi = false,
  });

  final List<T> items;
  final String Function(T item) labelOf;
  final bool Function(T item) isSelected;
  final ValueChanged<T> onTap;

  /// Null hides the search box.
  final TextEditingController? search;
  final bool loading;
  final ApiException? error;
  final VoidCallback? onRetry;

  /// Check boxes instead of a single check mark.
  final bool multi;

  static const _rowHeight = 52.0;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final Widget body;
    if (items.isEmpty && loading) {
      body = Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.ms, vertical: 8.ms),
        child: const Shimmer(child: SkeletonLines(lines: 6, height: 18)),
      );
    } else if (items.isEmpty && error != null) {
      body = CStateView.error(context, error!, onRetry: onRetry);
    } else if (items.isEmpty) {
      body = Padding(
        padding: EdgeInsets.all(24.ms),
        child: CText(
          'hostflow:picker.empty',
          size: 14,
          color: p.muted,
          align: TextAlign.center,
        ),
      );
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(horizontal: 12.ms),
        itemExtent: _rowHeight.ms,
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final selected = isSelected(item);
          return Pressable(
            onPressed: () => onTap(item),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.ms),
              decoration: BoxDecoration(
                color: selected ? p.tint : null,
                borderRadius: BorderRadius.circular(12.ms),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CText.raw(
                      labelOf(item),
                      size: 15,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: p.text,
                      maxLines: 1,
                    ),
                  ),
                  if (multi)
                    Icon(
                      selected ? LucideIcons.squareCheck : LucideIcons.square,
                      size: 20.ms,
                      color: selected ? p.accent : p.faint,
                    )
                  else if (selected)
                    Icon(LucideIcons.check, size: 20.ms, color: p.accent),
                ],
              ),
            ),
          );
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (search != null)
          Padding(
            padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 10.ms),
            child: HostSearchBox(
              controller: search!,
              hint: 'hostflow:picker.search',
            ),
          ),
        Flexible(child: body),
      ],
    );
  }
}
