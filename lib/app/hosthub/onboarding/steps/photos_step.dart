import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../common/host_review.dart';
import '../helper/draft_controller.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';
import '../helper/host_steps.dart';
import '../helper/photo_picker.dart';
import '../helper/photo_uploads.dart';
import '../helper/validation.dart';
import '../widgets/fix_notice.dart';
import '../widgets/photo_tile.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/step_body.dart';

/// 4 of 11: one to three photos, the first is the primary one.
class PhotosStep extends HookWidget {
  const PhotosStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) {
    final uploads = useMemoized(() => HostPhotoUploads(draft), [draft]);
    final p = HostPalette.of(context);
    final review = HostReviewScope.of(context);

    Future<void> add() async {
      final origin = await showHostSheet<HostPhotoOrigin>(
        context,
        title: 'hostflow:photos.sheet_title',
        name: 'host_photo_source_sheet',
        child: const _OriginOptions(),
      );
      if (origin != null) await uploads.add(origin);
    }

    return HostStepBody(
      title: 'hostflow:photos.title',
      subtitle: 'hostflow:photos.subtitle',
      children: [
        const HostFixNotice(step: HostStep.photos),
        LayoutBuilder(
          builder: (_, box) {
            final gap = 10.ms;
            const per = HostValidation.maxPhotos;
            final w = (box.maxWidth - gap * (per - 1)) / per;
            return ValueListenableBuilder<List<HostDraftPhoto>>(
              valueListenable: draft.photos,
              builder: (_, photos, _) {
                Widget slot(int i) => SizedBox(
                  width: w,
                  height: w * 1.45,
                  child: i < photos.length
                      ? HostPhotoTile(
                          key: ValueKey(photos[i].key),
                          photo: photos[i],
                          width: w,
                          primary: i == 0,
                          review: review.photoStatus(photos[i].mediaId),
                          onRemove: () => uploads.remove(photos[i]),
                          onTap: () {
                            final ph = photos[i];
                            if (ph.failed) {
                              uploads.retry(ph);
                            } else if (i > 0 && ph.uploaded) {
                              uploads.makePrimary(ph);
                            }
                          },
                        )
                      : i == photos.length && photos.length < per
                      ? HostAddPhotoTile(onTap: add)
                      : const SizedBox.shrink(),
                );
                // The 3 slots; a photo saved past them (an older app could
                // save a 4th) wraps onto the next row, so it can be removed.
                final count = photos.length > per ? photos.length : per;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [for (var i = 0; i < count; i++) slot(i)],
                );
              },
            );
          },
        ),
        ValueListenableBuilder<List<HostDraftPhoto>>(
          valueListenable: draft.photos,
          builder: (_, photos, _) => photos.length > HostValidation.maxPhotos
              ? Padding(
                  padding: EdgeInsets.only(top: 10.ms),
                  child: CText(
                    'hostflow:errors.photos_too_many',
                    variables: const {'max': HostValidation.maxPhotos},
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: p.danger,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        SizedBox(height: 20.ms),
        HostCard(
          color: p.tint,
          borderColor: p.tint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.lightbulb, size: 20.ms, color: p.accent),
                  SizedBox(width: 8.ms),
                  CText(
                    'hostflow:photos.tips_title',
                    size: 17,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
                ],
              ),
              SizedBox(height: 8.ms),
              for (final k in const ['tip1', 'tip2', 'tip3'])
                Padding(
                  padding: EdgeInsets.only(top: 6.ms),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.check, size: 16.ms, color: p.accent),
                      SizedBox(width: 8.ms),
                      Expanded(
                        child: CText(
                          'hostflow:photos.$k',
                          size: 14.5,
                          weight: FontWeight.w500,
                          color: p.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 12.ms),
        HostCard(
          color: p.dangerTint,
          borderColor: p.dangerTint,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user, size: 30.ms, color: p.danger),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      'hostflow:photos.real_title',
                      size: 15.5,
                      weight: FontWeight.w700,
                      color: p.text,
                    ),
                    SizedBox(height: 4.ms),
                    CText(
                      'hostflow:photos.real_body',
                      size: 14.5,
                      weight: FontWeight.w500,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OriginOptions extends StatelessWidget {
  const _OriginOptions();

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    Widget row(HostPhotoOrigin origin, IconData icon, String label) =>
        Pressable(
          onPressed: () => Navigator.of(context).pop(origin),
          child: Container(
            height: 56.ms,
            margin: EdgeInsets.only(bottom: 10.ms),
            padding: EdgeInsets.symmetric(horizontal: 16.ms),
            decoration: BoxDecoration(
              color: p.tint,
              borderRadius: BorderRadius.circular(14.ms),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22.ms, color: p.accent),
                SizedBox(width: 12.ms),
                Expanded(
                  child: CText(
                    label,
                    size: 17,
                    weight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.ms),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(
            HostPhotoOrigin.gallery,
            LucideIcons.images,
            'hostflow:photos.gallery',
          ),
          row(
            HostPhotoOrigin.camera,
            LucideIcons.camera,
            'hostflow:photos.camera',
          ),
        ],
      ),
    );
  }
}
