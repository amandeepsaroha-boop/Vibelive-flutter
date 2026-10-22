import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/draft_models.dart';
import '../helper/host_palette.dart';

/// One profile photo: the picked file while it uploads, then the uploaded
/// image (decoded at tile size). Slot 1 wears the "Primary" badge.
class HostPhotoTile extends StatelessWidget {
  const HostPhotoTile({
    super.key,
    required this.photo,
    required this.width,
    required this.primary,
    required this.onRemove,
    required this.onTap,
  });

  final HostDraftPhoto photo;
  final double width;
  final bool primary;
  final VoidCallback onRemove;

  /// Retry a failed upload, or make this photo the primary one.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final radius = 14.ms;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final placeholder = Container(
      color: p.tint,
      alignment: Alignment.center,
      child: Icon(LucideIcons.image, size: 22.ms, color: p.faint),
    );
    final local = photo.localPath;
    final Widget image = photo.url != null
        ? CImage(
            url: photo.url,
            width: width,
            placeholder: placeholder,
            errorWidget: local == null ? placeholder : null,
          )
        : local != null
        ? Image.file(
            File(local),
            width: width,
            fit: BoxFit.cover,
            cacheWidth: (width * dpr).round(),
            errorBuilder: (_, _, _) => placeholder,
          )
        : placeholder;

    return Pressable(
      activeOpacity: 0.9,
      onPressed: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (photo.uploading || photo.failed)
              ColoredBox(
                color: AppColors.blackA(0.35),
                child: Center(
                  child: photo.failed
                      ? Icon(
                          LucideIcons.refreshCw,
                          size: 22.ms,
                          color: AppColors.white,
                        )
                      : SizedBox.square(
                          dimension: 22.ms,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.white,
                          ),
                        ),
                ),
              ),
            if (primary)
              Positioned(
                left: 6.ms,
                top: 6.ms,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.ms,
                    vertical: 3.ms,
                  ),
                  decoration: BoxDecoration(
                    gradient: p.buttonGradient,
                    borderRadius: BorderRadius.circular(8.ms),
                  ),
                  child: CText(
                    'hostflow:photos.primary',
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: p.onAccent,
                  ),
                ),
              ),
            Positioned(
              right: 4.ms,
              top: 4.ms,
              child: Pressable(
                onPressed: onRemove,
                semanticLabel: context.t('hostflow:photos.remove'),
                hitPadding: EdgeInsets.all(4.ms),
                child: Container(
                  width: 24.ms,
                  height: 24.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.blackA(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.x,
                    size: 14.ms,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed "+ Add photo" slot.
class HostAddPhotoTile extends StatelessWidget {
  const HostAddPhotoTile({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Pressable(
      onPressed: onTap,
      child: CustomPaint(
        painter: _DashedBox(p.tintBorder, 14.ms),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.tint.withValues(alpha: p.tint.a * 0.6),
            borderRadius: BorderRadius.circular(14.ms),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plus, size: 26.ms, color: p.accent),
              SizedBox(height: 6.ms),
              CText(
                'hostflow:photos.add',
                size: 13.5,
                weight: FontWeight.w600,
                color: p.muted,
                align: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBox extends CustomPainter {
  const _DashedBox(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.75);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 5.0, gap = 4.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) =>
      old.color != color || old.radius != radius;
}
