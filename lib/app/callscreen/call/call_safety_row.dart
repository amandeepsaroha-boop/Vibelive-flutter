import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// Sizes of a [CallSafetyRow]: boxes already scaled (the incoming card uses
/// `s`/`vs`, the in-call panel `ms`); [label] / [hint] are font sizes before
/// `CText` scales them.
typedef SafetyRowSizes = ({
  double disc,
  double icon,
  double gap,
  double padV,
  double label,
  double hint,
  double hintGap,
});

/// One "Block / Report" row of the incoming safety card and the in-call
/// panel: disc with glyph (spinner while [busy]), label and hint. At 40 %
/// while the other row runs; no taps while either does.
class CallSafetyRow extends StatelessWidget {
  const CallSafetyRow({
    super.key,
    required this.sizes,
    required this.icon,
    required this.label,
    required this.hint,
    required this.busy,
    required this.otherBusy,
    required this.onPressed,
    this.labelVariables,
    this.labelRaw = false,
    this.divider = false,
  });

  final SafetyRowSizes sizes;
  final IconData icon;

  /// i18n key (or literal text with [labelRaw]).
  final String label;
  final Map<String, dynamic>? labelVariables;
  final bool labelRaw;
  final String hint;
  final bool busy;
  final bool otherBusy;
  final VoidCallback onPressed;

  /// Hairline above (2nd row of the incoming card).
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final z = sizes;
    final row = Container(
      padding: EdgeInsets.symmetric(vertical: z.padV),
      decoration: divider
          ? BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.whiteA(0.08))),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: z.disc,
            height: z.disc,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.whiteA(0.10),
              shape: BoxShape.circle,
            ),
            child: busy
                ? SizedBox.square(
                    // RN small ActivityIndicator.
                    dimension: math.min(20, z.disc - 6),
                    child: const RepaintBoundary(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    ),
                  )
                : Icon(icon, size: z.icon, color: AppColors.white, weight: 600),
          ),
          SizedBox(width: z.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                labelRaw
                    ? CText.raw(
                        label,
                        color: AppColors.white,
                        size: z.label,
                        weight: FontWeight.w800,
                        maxLines: 1,
                      )
                    : CText(
                        label,
                        variables: labelVariables,
                        color: AppColors.white,
                        size: z.label,
                        weight: FontWeight.w800,
                        maxLines: 1,
                      ),
                SizedBox(height: z.hintGap),
                CText(
                  hint,
                  color: AppColors.whiteA(0.45),
                  size: z.hint,
                  weight: FontWeight.w600,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: otherBusy ? 0.4 : 1,
      child: Pressable(
        onPressed: busy || otherBusy ? null : onPressed,
        activeOpacity: 0.85,
        child: row,
      ),
    );
  }
}
