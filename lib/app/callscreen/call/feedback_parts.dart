import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// Handle, "RATE YOUR CALL EXPERIENCE", "How was your session with …?".
class FeedbackHead extends StatelessWidget {
  const FeedbackHead({super.key, required this.name});
  final String? name;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 44.sw,
        height: 5,
        margin: EdgeInsets.only(bottom: 24.vs),
        decoration: BoxDecoration(
          color: AppColors.whiteA(0.12),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      const CText(
        'call:feedback.title',
        uppercase: true,
        color: AppColors.white,
        size: 20,
        weight: FontWeight.w900,
        letterSpacing: 0.5,
        align: TextAlign.center,
      ),
      SizedBox(height: 6.vs),
      CText(
        name == null
            ? 'call:feedback.subtitle'
            : 'call:feedback.subtitle_named',
        variables: name == null ? null : {'name': name},
        color: AppColors.whiteA(0.5),
        size: 13,
        weight: FontWeight.w500,
        align: TextAlign.center,
      ),
    ],
  );
}

/// Five square star buttons (RN 54, gap s12); they shrink to fit a narrow
/// phone instead of overflowing.
class FeedbackStars extends StatelessWidget {
  const FeedbackStars({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gap = 12.sw;
    return LayoutBuilder(
      builder: (_, box) {
        final side = math.min(54.ms, (box.maxWidth - gap * 4) / 5);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var n = 1; n <= 5; n++) ...[
              if (n > 1) SizedBox(width: gap),
              Pressable(
                onPressed: () => onChanged(n),
                activeOpacity: 0.7,
                semanticLabel: context.t(
                  'call:history.review.star',
                  variables: {'value': n},
                ),
                child: _Star(side: side, active: n <= value, colors: c),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.side, required this.active, required this.colors});

  final double side;
  final bool active;
  final VibeColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: active ? c.accentA(0.10) : AppColors.whiteA(0.03),
        borderRadius: BorderRadius.circular(18.ms),
        border: Border.all(
          color: active ? c.accentA(0.40) : AppColors.whiteA(0.06),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: c.accentA(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(
        active ? Icons.star : Icons.star_border,
        size: math.min(32.ms, side * 0.6),
        color: active ? c.accent : AppColors.whiteA(0.3),
      ),
    );
  }
}

/// Optional comment (≤ 300 characters), accent border while focused.
class FeedbackComment extends HookWidget {
  const FeedbackComment({
    super.key,
    required this.controller,
    required this.formatters,
  });

  final TextEditingController controller;
  final List<TextInputFormatter> formatters;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focus = useFocusNode();
    final focused = useListenableSelector(focus, () => focus.hasFocus);
    final text = TextStyle(fontSize: 13.ms, color: AppColors.white);
    return MediaQuery.withNoTextScaling(
      child: Container(
        height: 90.vs,
        decoration: BoxDecoration(
          color: focused ? c.accentA(0.02) : AppColors.whiteA(0.02),
          borderRadius: BorderRadius.circular(20.ms),
          border: Border.all(
            color: focused ? c.accent : AppColors.whiteA(0.06),
          ),
        ),
        padding: EdgeInsets.all(14.ms),
        child: TextField(
          controller: controller,
          focusNode: focus,
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          inputFormatters: formatters,
          cursorColor: c.accent,
          style: text,
          // `InputDecoration.collapsed`, minus its label animation: with
          // nothing to float, focusing must not re-lay out the sheet for
          // 167 ms.
          decoration: InputDecoration(
            isCollapsed: true,
            isDense: false,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            hintText: context.t('call:feedback.placeholder'),
            hintStyle: text.copyWith(color: AppColors.whiteA(0.4)),
          ),
        ),
      ),
    );
  }
}

/// Neo-brutalist submit: accent fill with a hard black shadow; 15 % accent
/// and no shadow until a star is picked.
class FeedbackSubmit extends StatelessWidget {
  const FeedbackSubmit({
    super.key,
    required this.enabled,
    required this.onPressed,
    this.loading = false,
  });

  final bool enabled;
  final VoidCallback onPressed;

  /// The review is being sent: a spinner in place of the label, no taps.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: enabled && !loading ? onPressed : null,
      activeOpacity: 0.86,
      child: Container(
        width: double.infinity,
        height: 54.vs,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? c.accent : c.accentA(0.15),
          borderRadius: BorderRadius.circular(20.ms),
          boxShadow: enabled
              ? const [BoxShadow(color: AppColors.black, offset: Offset(3, 3))]
              : null,
        ),
        child: loading
            ? SizedBox.square(
                dimension: 20,
                child: RepaintBoundary(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.onAccent,
                  ),
                ),
              )
            : CText(
                'call:feedback.submit',
                uppercase: true,
                color: c.onAccent,
                size: 14,
                weight: FontWeight.w900,
                letterSpacing: 1.5,
                maxLines: 1,
              ),
      ),
    );
  }
}
