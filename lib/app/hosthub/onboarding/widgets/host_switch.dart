import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';

/// The design's pill switch: accent gradient when on, grey track when off.
/// Only the knob animates (implicitly), nothing around it rebuilds.
class HostSwitch extends StatelessWidget {
  const HostSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.width = 50,
    this.height = 30,
    this.onDark = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  final double width;
  final double height;

  /// On a filled accent button (the "Go online" bar): a translucent track.
  final bool onDark;

  /// Knob slide and fill fade.
  static const duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final w = width.ms;
    final h = height.ms;
    final knob = h - 6.ms;
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: Pressable(
        activeOpacity: 0.85,
        onPressed: onChanged == null ? null : () => onChanged!(!value),
        // A fixed track with the "on" fill faded over it, so the colour
        // never dips through transparent; the knob slides.
        child: RepaintBoundary(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(h),
                      color: onDark ? AppColors.whiteA(0.16) : p.track,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: value ? 1 : 0,
                    duration: duration,
                    curve: Curves.easeInOut,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(h),
                        color: onDark ? AppColors.whiteA(0.28) : null,
                        gradient: onDark ? null : p.buttonGradient,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(3.ms),
                  child: AnimatedAlign(
                    duration: duration,
                    curve: Curves.easeInOut,
                    alignment: value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
