import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';

/// "Use current location" link above the state / district pickers. Shows a
/// spinner and "Finding your location…" while [locating].
class UseLocationButton extends StatelessWidget {
  const UseLocationButton({
    super.key,
    required this.locating,
    required this.onPressed,
  });

  final ValueNotifier<bool> locating;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return ValueListenableBuilder<bool>(
      valueListenable: locating,
      builder: (_, busy, _) => Align(
        alignment: Alignment.centerLeft,
        child: Pressable(
          onPressed: busy ? null : onPressed,
          hitPadding: EdgeInsets.all(8.ms),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 4.ms),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: 16.ms,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else
                  Icon(LucideIcons.locateFixed, size: 16.ms, color: accent),
                SizedBox(width: 8.ms),
                // Wraps on a narrow phone / in Hindi rather than overflow.
                Flexible(
                  child: CText(
                    busy ? 'client:location.locating' : 'client:location.use',
                    size: 13.5,
                    weight: FontWeight.w800,
                    color: accent,
                    maxLines: 2,
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
