import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/skeleton.dart';
import '../helper/me_palette.dart';

/// First-load placeholder shaped like the ME tab: the profile card (avatar,
/// name, handle, pill), then three list cards.
class MeSkeleton extends StatelessWidget {
  const MeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final card = SkeletonBox(height: 80.ms, radius: 28.ms);
    return ClipRect(
      child: Padding(
        padding: EdgeInsets.fromLTRB(10.ms, 6.ms, 10.ms, 0),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(18.ms, 28.ms, 18.ms, 16.ms),
                decoration: BoxDecoration(
                  color: p.profileBg,
                  borderRadius: BorderRadius.circular(32.ms),
                  border: Border.all(color: p.profileBorder),
                ),
                child: Shimmer(
                  child: Column(
                    children: [
                      SkeletonBox(width: 116.ms, height: 116.ms, circle: true),
                      SizedBox(height: 16.ms),
                      SkeletonBox(width: 170.ms, height: 24.ms, radius: 8),
                      SizedBox(height: 8.ms),
                      SkeletonBox(width: 90.ms, height: 14.ms, radius: 7),
                      SizedBox(height: 12.ms),
                      SkeletonBox(width: 160.ms, height: 30.ms, radius: 15),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16.ms),
              Shimmer(
                child: Column(
                  children: [
                    card,
                    SizedBox(height: 12.ms),
                    card,
                    SizedBox(height: 12.ms),
                    card,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
