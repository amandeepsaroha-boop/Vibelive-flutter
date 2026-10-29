import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/analytics/events/me_events.dart';
import '../../core/analytics/screen_tracker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import 'c_text.dart';
import 'pressable.dart';

/// A profile link as a QR code (RN profile QR modal). [source]: where it
/// was opened, for analytics.
Future<void> showQrCodeSheet(
  BuildContext context, {
  required String url,
  required String name,
  String handle = '',
  String? source,
}) {
  UiEvents.qrShown(source: source);
  return _showQr(context, url: url, name: name, handle: handle);
}

Future<void> _showQr(
  BuildContext context, {
  required String url,
  required String name,
  required String handle,
}) => showGeneralDialog<void>(
  context: context,
  routeSettings: ScreenTracker.sheet('qr_code_sheet'),
  barrierDismissible: true,
  barrierLabel: 'qr',
  barrierColor: const Color(0xEB050508),
  transitionDuration: const Duration(milliseconds: 180),
  transitionBuilder: (_, a, _, child) =>
      FadeTransition(opacity: a, child: child),
  pageBuilder: (ctx, _, _) {
    final c = ctx.colors;
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 340.ms.clamp(0, MediaQuery.sizeOf(ctx).width * 0.9),
          padding: EdgeInsets.all(24.ms),
          decoration: BoxDecoration(
            color: c.isDark ? AppColors.darkSurface : AppColors.white,
            borderRadius: BorderRadius.circular(32.ms),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CText(
                      'qr.title',
                      size: 18,
                      weight: FontWeight.w900,
                      color: c.text,
                    ),
                  ),
                  Pressable(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: 32.ms,
                      height: 32.ms,
                      decoration: BoxDecoration(
                        color: c.surfaceVariant,
                        borderRadius: BorderRadius.circular(12.ms),
                        border: Border.all(color: c.border),
                      ),
                      child: Icon(LucideIcons.x, size: 16.ms, color: c.text),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.ms),
              Container(
                padding: EdgeInsets.all(20.ms),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(24.ms),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: QrImageView(
                  data: url,
                  size: 200.ms,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: AppColors.white,
                ),
              ),
              SizedBox(height: 20.ms),
              CText.raw(
                name,
                size: 20,
                weight: FontWeight.w900,
                color: c.text,
                align: TextAlign.center,
              ),
              if (handle.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 4.ms),
                  child: CText.raw(
                    '@${handle.toLowerCase()}',
                    size: 13,
                    weight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
              SizedBox(height: 10.ms),
              CText(
                'qr.hint',
                size: 12,
                color: c.textMuted,
                align: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  },
);
