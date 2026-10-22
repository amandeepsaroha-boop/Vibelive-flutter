import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';

/// Multi-line note of the review and report sheets (RN `TextInput
/// multiline`). [placeholder] is an i18n key. Not scaled by the OS font size.
class HistoryNoteField extends StatelessWidget {
  const HistoryNoteField({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.minLines,
    this.radius = 12,
    this.highlighted = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final int minLines;

  /// Unscaled corner radius.
  final double radius;

  /// Accent border (RN: the review comment has text).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final border = highlighted
        ? c.accent
        : (dark ? AppColors.whiteA(0.12) : AppColors.blackA(0.12));
    return MediaQuery.withNoTextScaling(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 12.ms),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius.ms),
          border: Border.all(color: border),
        ),
        child: TextField(
          controller: controller,
          minLines: minLines,
          maxLines: minLines + 3,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: c.accent,
          style: TextStyle(
            fontSize: 14.ms,
            height: 20 / 14,
            color: c.modalText,
          ),
          // `InputDecoration.collapsed`, minus its label animation: with
          // nothing to float, focusing must not re-lay out the sheet for
          // 167 ms.
          decoration: InputDecoration(
            isCollapsed: true,
            isDense: false,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            hintText: context.t(placeholder),
            hintStyle: TextStyle(
              fontSize: 14.ms,
              height: 20 / 14,
              color: dark ? AppColors.whiteA(0.35) : AppColors.blackA(0.35),
            ),
          ),
        ),
      ),
    );
  }
}
