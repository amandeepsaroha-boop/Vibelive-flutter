import 'package:flutter/widgets.dart';

import '../../core/constants/app_assets.dart';

/// RN `AppLogo`: the in-app "vibe live" wordmark, contained in a square.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 200, this.height});

  /// The artwork is 1567 × 426 px.
  static const aspect = 426 / 1567;

  final double size;

  /// The wordmark is wide: a height drops the empty band a square leaves
  /// (e.g. `size * AppLogo.aspect`). Defaults to [size].
  final double? height;

  /// Decoded at display size, not the 1567px source. Use it to precache.
  static ImageProvider provider(BuildContext context, double size) =>
      ResizeImage.resizeIfNeeded(
        (size * MediaQuery.devicePixelRatioOf(context)).round(),
        null,
        const AssetImage(AppImages.inAppLogo),
      );

  @override
  Widget build(BuildContext context) {
    return Image(
      image: provider(context, size),
      width: size,
      height: height ?? size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      semanticLabel: 'Vibe Live',
    );
  }
}
