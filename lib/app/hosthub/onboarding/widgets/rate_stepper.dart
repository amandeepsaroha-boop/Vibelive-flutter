import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';

/// "−  ₹ 25 / min  +". Listens to [rate] itself.
///
/// [min] is the backend's own minimum (₹7, say), not rounded: the first
/// "+" goes to the next multiple of [step] (₹10) and on in steps, "−" back
/// down the same way and never below [min]. Holding a button repeats.
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

  /// The next rate up from [v]: the next multiple of [step].
  static int up(int v, {required int step, required int max}) {
    final next = (v ~/ step + 1) * step;
    return next > max ? max : next;
  }

  /// The next rate down from [v]: the multiple of [step] below, never
  /// under [min].
  static int down(int v, {required int step, required int min}) {
    final next = ((v - 1) ~/ step) * step;
    return next < min ? min : next;
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: rate,
      builder: (_, v, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: LucideIcons.minus,
            label:
                '${semanticPrefix ?? ''} ${context.t('hostflow:rates.decrease')}'
                    .trim(),
            enabled: enabled && v > min,
            onStep: () => rate.value = down(rate.value, step: step, min: min),
          ),
          SizedBox(width: 8.ms),
          // Shrinks (the amount scales down) rather than overflow on a
          // narrow phone or in Hindi.
          Flexible(
            child: Container(
              height: 40.ms,
              constraints: BoxConstraints(minWidth: 96.ms),
              padding: EdgeInsets.symmetric(horizontal: 12.ms),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.neutral,
                borderRadius: BorderRadius.circular(12.ms),
                border: Border.all(color: p.cardBorder),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    CText(
                      'hostflow:rates.amount',
                      variables: {'amount': v},
                      size: 18,
                      weight: FontWeight.w800,
                      color: p.text,
                    ),
                    SizedBox(width: 4.ms),
                    CText(
                      'hostflow:rates.per_min_short',
                      size: 13,
                      weight: FontWeight.w600,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 8.ms),
          _StepButton(
            icon: LucideIcons.plus,
            label:
                '${semanticPrefix ?? ''} ${context.t('hostflow:rates.increase')}'
                    .trim(),
            enabled: enabled && v < max,
            onStep: () => rate.value = up(rate.value, step: step, max: max),
          ),
        ],
      ),
    );
  }
}

/// A round − / + that also repeats while held.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onStep,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onStep;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final on = widget.enabled;
    return GestureDetector(
      onLongPressStart: on
          ? (_) => _repeat = Timer.periodic(
              const Duration(milliseconds: 110),
              (_) => widget.onStep(),
            )
          : null,
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: Pressable(
        onPressed: on ? widget.onStep : null,
        semanticLabel: widget.label,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: on ? 1 : 0.35,
          child: Container(
            width: 40.ms,
            height: 40.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.neutral,
              shape: BoxShape.circle,
              border: Border.all(color: p.cardBorder),
            ),
            child: Icon(widget.icon, size: 18.ms, color: p.text),
          ),
        ),
      ),
    );
  }
}
