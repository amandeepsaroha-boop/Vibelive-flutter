import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics/events/me_events.dart';
import '../../core/utils/log.dart';
import '../../core/utils/scale.dart';
import 'c_toast.dart';

/// The OS share sheet. Falls back to copying the text when the sheet can't
/// open (simulator quirks, no share targets).
abstract final class AppShare {
  /// [anchor]: the widget that was tapped, so iPad points the sheet at it.
  /// [contentType]: what is shared, for analytics (`share_sheet_result`).
  static Future<void> text(
    String message, {
    RenderObject? anchor,
    String? subject,
    String contentType = 'text',
  }) async {
    final origin = anchor is RenderBox && anchor.hasSize
        ? anchor.localToGlobal(Offset.zero) & anchor.size
        : Rect.fromCenter(
            center: Offset(Scale.screenWidth / 2, Scale.screenHeight / 2),
            width: 1,
            height: 1,
          );
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: subject,
          sharePositionOrigin: origin,
        ),
      );
      UiEvents.shareSheet(
        contentType: contentType,
        result: switch (result.status) {
          ShareResultStatus.success => 'shared',
          ShareResultStatus.dismissed => 'dismissed',
          ShareResultStatus.unavailable => 'unavailable',
        },
      );
    } catch (e) {
      Log.w('AppShare', 'share sheet unavailable, copying: $e');
      await Clipboard.setData(ClipboardData(text: message));
      CToast.show('share.copied', variant: CToastVariant.success);
      UiEvents.shareSheet(contentType: contentType, result: 'copied');
    }
  }
}
