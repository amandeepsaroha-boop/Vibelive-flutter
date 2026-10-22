import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// 44pt square icon button of the top bars (RN `IconBtn`), with an
/// optional count badge.
class TopBarButton extends StatelessWidget {
  const TopBarButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.color,
    this.badge = 0,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final Color? color;
  final int badge;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: Container(
        width: 44.ms,
        height: 44.ms,
        decoration: BoxDecoration(
          color: c.isDark ? AppColors.whiteA(0.05) : AppColors.blackA(0.04),
          borderRadius: BorderRadius.circular(14.ms),
          border: Border.all(
            color: c.isDark ? AppColors.whiteA(0.12) : AppColors.blackA(0.09),
          ),
        ),
        child: Icon(icon, size: 18.ms, color: color ?? c.text),
      ),
    );
    final withLongPress = onLongPress == null
        ? button
        : GestureDetector(onLongPress: onLongPress, child: button);
    if (badge <= 0) return withLongPress;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        withLongPress,
        Positioned(
          top: -4.ms,
          right: -4.ms,
          child: Container(
            width: 16.ms,
            height: 16.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            child: CText.raw(
              '$badge',
              size: 9,
              weight: FontWeight.w900,
              color: c.onAccent,
            ),
          ),
        ),
      ],
    );
  }
}
