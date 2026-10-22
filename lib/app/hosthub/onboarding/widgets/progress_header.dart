import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';
import '../helper/host_steps.dart';

/// Back chevron, progress bar and "N of 11". Listens to [step] itself, so a
/// step change repaints only this row.
class HostProgressHeader extends StatelessWidget {
  const HostProgressHeader({
    super.key,
    required this.step,
    required this.onBack,
  });

  final ValueListenable<HostStep> step;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 6.ms, 20.ms, 6.ms),
      child: Row(
        children: [
          Pressable(
            onPressed: onBack,
            semanticLabel: context.t('hostflow:back'),
            hitPadding: EdgeInsets.all(4.ms),
            child: Container(
              width: 42.ms,
              height: 42.ms,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.neutral,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.chevronLeft, size: 22.ms, color: p.text),
            ),
          ),
          SizedBox(width: 14.ms),
          Expanded(
            child: ValueListenableBuilder<HostStep>(
              valueListenable: step,
              builder: (_, s, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: s.number / HostStep.total),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => _Bar(value: v, palette: p),
              ),
            ),
          ),
          SizedBox(width: 14.ms),
          ValueListenableBuilder<HostStep>(
            valueListenable: step,
            builder: (_, s, _) => CText(
              'hostflow:progress',
              variables: {'current': s.number, 'total': HostStep.total},
              size: 14.5,
              weight: FontWeight.w600,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.palette});
  final double value;
  final HostPalette palette;

  @override
  Widget build(BuildContext context) {
    final h = 5.ms;
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: palette.track,
        borderRadius: BorderRadius.circular(h),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: palette.buttonGradient,
            borderRadius: BorderRadius.circular(h),
          ),
          child: SizedBox(height: h),
        ),
      ),
    );
  }
}
