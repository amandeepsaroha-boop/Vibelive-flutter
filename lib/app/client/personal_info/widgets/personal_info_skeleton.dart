import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/skeleton.dart';
import '../helper/personal_info_palette.dart';
import 'photo_header.dart';

/// First-load placeholder shaped like the form: the avatar band, then a
/// section label and five labelled fields.
class PersonalInfoSkeleton extends StatelessWidget {
  const PersonalInfoSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    final avatar = PhotoHeader.avatarSize;
    Widget field() => Padding(
      padding: EdgeInsets.only(bottom: 18.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 90.ms, height: 12.ms, radius: 6),
          SizedBox(height: 10.ms),
          SkeletonBox(height: 56.ms, radius: 16.ms),
        ],
      ),
    );
    return ClipRect(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20.ms, 24.ms, 20.ms, 20.ms),
              decoration: BoxDecoration(
                color: p.card,
                border: Border.symmetric(
                  horizontal: BorderSide(color: p.border),
                ),
              ),
              child: Shimmer(
                child: Column(
                  children: [
                    SkeletonBox(width: avatar, height: avatar, circle: true),
                    SizedBox(height: 12.ms),
                    SkeletonBox(width: 240.ms, height: 10.ms, radius: 5),
                    SizedBox(height: 6.ms),
                    SkeletonBox(width: 180.ms, height: 10.ms, radius: 5),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: p.card,
              padding: EdgeInsets.fromLTRB(20.ms, 28.ms, 20.ms, 0),
              child: Shimmer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 70.ms, height: 10.ms, radius: 5),
                    SizedBox(height: 14.ms),
                    for (var i = 0; i < 5; i++) field(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
