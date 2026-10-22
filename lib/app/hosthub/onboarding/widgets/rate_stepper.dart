import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';

/// "−  ₹ 25 / minute  +". Listens to [rate] itself.
class HostRateStepper extends StatelessWidget {
  const HostRateStepper({
    super.key,
    required this.rate,
    required this.min,
    required this.max,
    required this.step,
    this.enabled = true,
    this.semanticPrefix,
  });

  final ValueNotifier<int> rate;
  final int min;
  final int max;
  final int step;
  final bool enabled;

  /// Distinguishes the audio and video steppers for screen readers.
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    Widget button(IconData icon, String label, int delta) =>
        ValueListenableBuilder<int>(
          valueListenable: rate,
          builder: (_, v, _) {
            final next = (v + delta).clamp(min, max);
            final can = enabled && next != v;
            return Pressable(
              onPressed: can ? () => rate.value = next : null,
              semanticLabel: '${semanticPrefix ?? ''} ${context.t(label)}'
                  .trim(),
              child: Opacity(
                opacity: can ? 1 : 0.4,
                child: Container(
                  width: 44.ms,
                  height: 44.ms,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.neutral,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.cardBorder),
                  ),
                  child: Icon(icon, size: 18.ms, color: p.text),
                ),
              ),
            );
          },
        );

    return Row(
      children: [
        button(LucideIcons.minus, 'hostflow:rates.decrease', -step),
        SizedBox(width: 10.ms),
        Expanded(
          child: Container(
            height: 44.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.neutral,
              borderRadius: BorderRadius.circular(12.ms),
            ),
            child: ValueListenableBuilder<int>(
              valueListenable: rate,
              builder: (_, v, _) => FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    CText(
                      'hostflow:rates.amount',
                      variables: {'amount': v},
                      size: 20,
                      weight: FontWeight.w800,
                      color: p.text,
                    ),
                    SizedBox(width: 6.ms),
                    CText(
                      'hostflow:rates.per_minute',
                      size: 14.5,
                      weight: FontWeight.w500,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 10.ms),
        button(LucideIcons.plus, 'hostflow:rates.increase', step),
      ],
    );
  }
}
