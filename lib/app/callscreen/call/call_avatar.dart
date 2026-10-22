import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import 'call_motion_widgets.dart';

/// Company accent of the incoming screen (RN `#60A5FA` / `#90CAF9`).
abstract final class CallColors {
  static const company = Color(0xFF60A5FA);
  static const companyRing = Color(0xFF90CAF9);
  static const companyPillBg = Color(0xFFE3F2FD);
  static const companyPillText = Color(0xFF1565C0);
  static const verifiedGreen = Color(0xFF00E676);
  static const callbackVoice = Color(0xFF0F8C70);

  /// rgba(28,28,30,.92) / .96: the safety card and panel.
  static const safetyCard = Color(0xEB1C1C1E);
  static const safetyPanel = Color(0xF51C1C1E);
}

/// The big ringed photo of both call screens (RN avatar ring View): [size]
/// circle, 4 pt [color] border, 4 pt gap, photo or a user glyph on 10 %
/// white. [companyRing] adds the incoming screen's expanding blue ring.
class CallAvatarRing extends StatelessWidget {
  const CallAvatarRing({
    super.key,
    required this.size,
    required this.color,
    required this.url,
    this.companyRing = false,
  });

  final double size;
  final Color color;
  final String? url;
  final bool companyRing;

  @override
  Widget build(BuildContext context) {
    final inner = size - 16;
    final glyph = Center(
      child: Icon(LucideIcons.user, size: 60.ms, color: AppColors.white),
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (companyRing)
            Positioned(
              left: -4,
              top: -4,
              right: -4,
              bottom: -4,
              child: IgnorePointer(
                child: PingPong(
                  leg: const Duration(milliseconds: 1800),
                  scaleTo: 1.3,
                  opacityFrom: 0.6,
                  opacityTo: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: CallColors.companyRing,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 4),
              ),
              child: ClipOval(
                child: ColoredBox(
                  color: AppColors.whiteA(0.10),
                  child: (url ?? '').isEmpty
                      ? glyph
                      : CImage(
                          url: url,
                          width: inner,
                          height: inner,
                          placeholder: glyph,
                          errorWidget: glyph,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// RN `renderAvatarTile`: a centred photo / letter circle on [background];
/// [full] (video layer) is a 132 circle with the name under it, otherwise
/// a 48 circle (PiP).
class CallAvatarTile extends StatelessWidget {
  const CallAvatarTile({
    super.key,
    required this.name,
    required this.url,
    this.full = false,
    this.background,
  });

  final String name;
  final String? url;
  final bool full;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final d = (full ? 132 : 48).sw;
    final letter = Container(
      alignment: Alignment.center,
      color: CAvatar.colorFor(name),
      // RN sized this letter with `scale`, not `moderateScale`.
      child: CText.raw(
        CAvatar.letterFor(name),
        weight: FontWeight.w900,
        color: AppColors.white,
        style: TextStyle(fontSize: (full ? 54 : 22).sw),
      ),
    );
    return ColoredBox(
      color: background ?? AppColors.whiteA(0.06),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: d,
              height: d,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.whiteA(0.08),
                border: full
                    ? Border.all(color: AppColors.whiteA(0.18), width: 3)
                    : null,
              ),
              child: (url ?? '').isEmpty
                  ? letter
                  : CImage(
                      url: url,
                      width: d,
                      height: d,
                      placeholder: letter,
                      errorWidget: letter,
                    ),
            ),
            if (full)
              Padding(
                padding: EdgeInsets.fromLTRB(24.sw, 18.vs, 24.sw, 0),
                child: CText.raw(
                  name,
                  size: 18,
                  weight: FontWeight.w700,
                  color: AppColors.whiteA(0.9),
                  maxLines: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
