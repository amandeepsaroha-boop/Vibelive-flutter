import 'package:flutter/widgets.dart';

import '../../../../core/constants/app_assets.dart';

/// The intro's hero photo, decoded at the size it is shown (it fills the
/// top three quarters of the screen, cropped to cover).
abstract final class HostIntroImage {
  /// Share of the screen height the photo covers.
  static const heightFactor = 0.78;

  /// The photo's aspect ratio (1080 × 1620).
  static const _aspect = 1080 / 1620;

  static ImageProvider provider(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // BoxFit.cover: the decoded width must cover the wider of the two.
    final logical = [
      size.width,
      size.height * heightFactor * _aspect,
    ].reduce((a, b) => a > b ? a : b);
    return ResizeImage.resizeIfNeeded(
      (logical * dpr).round(),
      null,
      const AssetImage(AppImages.hostIntro),
    );
  }

  /// Warm the decode so the intro never shows the photo popping in. Safe
  /// to call repeatedly; never holds navigation for long (a slow decode
  /// just finishes on first paint).
  static Future<void> precache(BuildContext context) => precacheImage(
    provider(context),
    context,
    onError: (_, _) {},
  ).timeout(const Duration(milliseconds: 400), onTimeout: () {});
}
