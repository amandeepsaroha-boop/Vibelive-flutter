import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/app_logo.dart';
import '../helper/native/screen_capture_guard.dart';

/// Covers the whole app with black and the logo while a video call is being
/// screen-recorded or mirrored (iOS; see [ScreenCaptureGuard]), so the
/// recording shows the logo instead of the call. Mount once at the app root,
/// above every route, sheet and the PiP tile.
class CaptureShield extends StatefulWidget {
  const CaptureShield({super.key, required this.child});

  final Widget child;

  @override
  State<CaptureShield> createState() => _CaptureShieldState();
}

class _CaptureShieldState extends State<CaptureShield> {
  @override
  void initState() {
    super.initState();
    ScreenCaptureGuard.attach();
  }

  @override
  Widget build(BuildContext context) => Stack(
    textDirection: TextDirection.ltr,
    children: [
      widget.child,
      ValueListenableBuilder<bool>(
        valueListenable: ScreenCaptureGuard.shielded,
        builder: (_, shielded, _) => shielded
            ? Positioned.fill(
                // Absorbs touches too: nothing under it should be tappable
                // while it hides the call.
                child: ColoredBox(
                  color: AppColors.black,
                  child: Center(child: AppLogo(size: 200.ms)),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}
