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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: w,
          height: h,
          padding: EdgeInsets.all(3.ms),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h),
            color: onDark
                ? AppColors.whiteA(value ? 0.28 : 0.16)
                : (value ? null : p.track),
            gradient: !onDark && value ? p.buttonGradient : null,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
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
      ),
    );
  }
}
