import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';

/// RN `VibeBackground`: plain screen fill with a hairline at the top.
/// Put it first in a `Stack` (it fills the stack and ignores touches).
class VibeBackground extends StatelessWidget {
  const VibeBackground({super.key, this.dark});

  /// Forces a mode regardless of the app theme.
  final bool? dark;

  @override
  Widget build(BuildContext context) {
    final isDark = dark ?? context.colors.isDark;
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppColors.black : LightColors.background,
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.whiteA(0.03) : AppColors.blackA(0.03),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
