import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';

/// How an unselected chip looks.
enum HostChipTone { outline, tint }

/// Gender / language / topic chip. Selected: accent gradient, white label.
class HostChip extends StatelessWidget {
  const HostChip({
    super.key,
    required this.label,
    this.translate = true,
    this.selected = false,
    this.onTap,
    this.leading,
    this.tone = HostChipTone.outline,
    this.height = 50,
    this.center = true,
    this.fontSize = 15.5,
  });

  /// i18n key, or literal text when [translate] is false (server labels).
  final String label;
  final bool translate;
  final bool selected;
  final VoidCallback? onTap;

  /// Emoji or icon, shown in a small rounded square.
  final Widget? leading;
  final HostChipTone tone;
  final double height;
  final bool center;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final fg = selected ? p.onAccent : p.text;
    final text = translate
        ? CText(
            label,
            size: fontSize,
            weight: FontWeight.w600,
            color: fg,
            maxLines: 2,
            align: center ? TextAlign.center : TextAlign.start,
          )
        : CText.raw(
            label,
            size: fontSize,
            weight: FontWeight.w600,
            color: fg,
            maxLines: 2,
            align: center ? TextAlign.center : TextAlign.start,
          );
    return Semantics(
      selected: selected,
      child: Pressable(
        activeOpacity: 0.8,
        onPressed: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: BoxConstraints(minHeight: height.ms),
          padding: EdgeInsets.symmetric(
            horizontal: leading == null ? 16.ms : 10.ms,
            vertical: 6.ms,
          ),
          decoration: BoxDecoration(
            gradient: selected ? p.buttonGradient : null,
            color: selected
                ? null
                : (tone == HostChipTone.tint ? p.tint : p.card),
            borderRadius: BorderRadius.circular(14.ms),
            border: Border.all(
              color: selected || tone == HostChipTone.tint
                  ? AppColors.transparent
                  : p.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: center
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              if (leading != null) ...[
                Container(
                  width: 28.ms,
                  height: 28.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.whiteA(0.22) : p.tint,
                    borderRadius: BorderRadius.circular(8.ms),
                  ),
                  child: leading,
                ),
                SizedBox(width: 8.ms),
              ],
              Flexible(child: text),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round "+" chip (add a language).
class HostRoundChip extends StatelessWidget {
  const HostRoundChip({
    super.key,
    required this.icon,
    required this.onTap,
    this.semanticLabel,
    this.size = 50,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Pressable(
      onPressed: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: size.ms,
        height: size.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.card,
          shape: BoxShape.circle,
          border: Border.all(color: p.cardBorder),
        ),
        child: Icon(icon, size: 20.ms, color: p.text),
      ),
    );
  }
}
