import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/skeleton.dart';
import 'helper/history_layout.dart';

/// Placeholder shaped like the call-log cards: static card frames, with one
/// shimmer over the avatar and text blocks. Full screen on first load;
/// [HistorySkeleton.more] is the two-row load-more footer.
class HistorySkeleton extends StatelessWidget {
  const HistorySkeleton({super.key}) : _rows = 8, _fill = true;

  /// Load-more footer: two rows, sized to their content.
  const HistorySkeleton.more({super.key}) : _rows = 2, _fill = false;

  final int _rows;

  /// Fills (and clips to) the available height, like the list it replaces.
  final bool _fill;

  /// Name / time widths, so the rows don't look stamped.
  static const _nameWidths = [128.0, 96.0, 150.0, 112.0];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final extent = HistoryLayout.extent(ping: false);
    final frame = Padding(
      padding: EdgeInsets.only(bottom: HistoryLayout.gap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(HistoryLayout.radius),
          border: Border.all(
            color: c.isDark ? AppColors.whiteA(0.08) : AppColors.blackA(0.09),
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );

    Widget bones(int i) => Padding(
      padding: EdgeInsets.fromLTRB(
        HistoryLayout.padH + HistoryLayout.border,
        HistoryLayout.padV + HistoryLayout.border,
        HistoryLayout.padH + HistoryLayout.border,
        HistoryLayout.padV + HistoryLayout.border + HistoryLayout.gap,
      ),
      child: Row(
        children: [
          SkeletonBox(
            width: HistoryLayout.avatar,
            height: HistoryLayout.avatar,
            circle: true,
          ),
          SizedBox(width: 10.ms),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonBox(
                      width: _nameWidths[i % _nameWidths.length].ms,
                      height: 14.ms,
                      radius: 7,
                    ),
                    const Spacer(),
                    SkeletonBox(width: 40.ms, height: 12.ms, radius: 6),
                  ],
                ),
                SizedBox(height: 10.ms),
                Row(
                  children: [
                    SkeletonBox(width: 64.ms, height: 9.ms, radius: 4),
                    const Spacer(),
                    SkeletonBox(width: 104.ms, height: 9.ms, radius: 4),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final rows = Stack(
      children: [
        Column(
          children: [
            for (var i = 0; i < _rows; i++)
              SizedBox(height: extent, child: frame),
          ],
        ),
        Shimmer(
          child: Column(
            children: [
              for (var i = 0; i < _rows; i++)
                SizedBox(height: extent, child: bones(i)),
            ],
          ),
        ),
      ],
    );
    if (!_fill) return rows;
    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: rows,
      ),
    );
  }
}
