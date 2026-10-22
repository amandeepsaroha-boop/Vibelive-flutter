import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/skeleton.dart';
import '../helper/referral_palette.dart';
import 'referred_user_tile.dart';

/// First load: the code card, the two counters and a few user rows.
class ReferralSkeleton extends StatelessWidget {
  const ReferralSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    BoxDecoration card(double radius) => BoxDecoration(
      color: p.card,
      borderRadius: BorderRadius.circular(radius.ms),
      border: Border.all(color: p.border),
    );
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 0),
        children: [
          Container(
            padding: EdgeInsets.all(16.ms),
            decoration: card(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 130.ms, height: 10.ms, radius: 5.ms),
                SizedBox(height: 10.ms),
                SkeletonBox(width: 150.ms, height: 26.ms, radius: 8.ms),
                SizedBox(height: 10.ms),
                SkeletonBox(width: 220.ms, height: 12.ms, radius: 6.ms),
                SizedBox(height: 16.ms),
                SkeletonBox(height: 58.ms, radius: 24.ms),
              ],
            ),
          ),
          SizedBox(height: 12.ms),
          Row(
            children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) SizedBox(width: 12.ms),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(14.ms),
                    decoration: card(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 80.ms, height: 10.ms, radius: 5.ms),
                        SizedBox(height: 8.ms),
                        SkeletonBox(width: 40.ms, height: 22.ms, radius: 6.ms),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 16.ms),
          SkeletonBox(width: 140.ms, height: 12.ms, radius: 6.ms),
          SizedBox(height: 12.ms),
          for (var i = 0; i < 4; i++) const _RowSkeleton(),
        ],
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    return Container(
      height: (ReferredUserTile.extent - 10).ms,
      margin: EdgeInsets.only(bottom: 10.ms),
      padding: EdgeInsets.symmetric(horizontal: 14.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          SkeletonBox(width: 44.ms, height: 44.ms, circle: true),
          SizedBox(width: 12.ms),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120.ms, height: 12.ms, radius: 6.ms),
                SizedBox(height: 8.ms),
                SkeletonBox(width: 80.ms, height: 10.ms, radius: 5.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
