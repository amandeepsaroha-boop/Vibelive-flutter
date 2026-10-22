import 'package:flutter/widgets.dart';

import '../../../core/utils/scale.dart';
import '../../component/skeleton.dart';

/// Call buttons, about card and topics while a summary card's full profile
/// loads (same sizes as the real sections).
class ProfileBodySkeleton extends StatelessWidget {
  const ProfileBodySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: 14.ms);
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SkeletonBox(height: 54.ms, radius: 20.ms),
              ),
              SizedBox(width: 10.ms),
              Expanded(
                child: SkeletonBox(height: 54.ms, radius: 20.ms),
              ),
            ],
          ),
          SizedBox(height: 26.ms),
          SkeletonBox(height: 132.ms, radius: 22.ms),
          gap,
          SkeletonBox(height: 96.ms, radius: 20.ms),
          gap,
        ],
      ),
    );
  }
}

/// Two review cards while the first page loads.
class ReviewsSkeleton extends StatelessWidget {
  const ReviewsSkeleton({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ClipRect(
      child: Shimmer(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.ms),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBox(width: 260.ms, height: height, radius: 20.ms),
                SizedBox(width: 12.ms),
                SkeletonBox(width: 260.ms, height: height, radius: 20.ms),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One review card while the next page of reviews loads (card size; brings
/// its own `Shimmer`).
class ReviewCardSkeleton extends StatelessWidget {
  const ReviewCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: SkeletonBox(width: 260.ms, height: double.infinity, radius: 20.ms),
  );
}
