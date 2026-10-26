import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';
import '../helper/host_steps.dart';
import '../helper/section_save.dart';
import '../helper/validation.dart';

/// The design's sentence-case gradient button ("Continue →"). `CButton`
/// always upper-cases its label with wide tracking, which the design does
/// not, hence this local one.
class HostButton extends StatelessWidget {
  const HostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.arrow = true,
    this.height = 58,
    this.colors,
    this.foreground,
  });

  /// i18n key.
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool arrow;
  final double height;

  /// Fixed colors (the always-dark intro keeps the brand purple).
  final List<Color>? colors;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final fg = foreground ?? p.onAccent;
    final gradient = colors == null
        ? p.buttonGradient
        : LinearGradient(colors: colors!);
    return Pressable(
      activeOpacity: 0.85,
      onPressed: loading ? null : onPressed,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onPressed == null && !loading ? 0.45 : 1,
        child: Container(
          height: height.ms,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 16.ms),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(14.ms),
          ),
          child: loading
              ? SizedBox.square(
                  dimension: 22.ms,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: CText(
                        label,
                        size: 17,
                        weight: FontWeight.w700,
                        color: fg,
                        maxLines: 1,
                      ),
                    ),
                    if (arrow) ...[
                      SizedBox(width: 8.ms),
                      Icon(LucideIcons.arrowRight, size: 18.ms, color: fg),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Sticky footer of every step: the step's primary action above the home
/// indicator. Rebuilds only on step / busy changes.
class HostContinueBar extends StatelessWidget {
  const HostContinueBar({
    super.key,
    required this.step,
    required this.busy,
    required this.notice,
    required this.onPressed,
    this.agreed,
    this.onSave,
    this.savesInstead = false,
  });

  final ValueListenable<HostStep> step;
  final ValueListenable<bool> busy;

  /// Why Continue was refused; shown above the button (a floating toast
  /// would sit right on top of it).
  final ValueListenable<HostIssue?> notice;
  final VoidCallback onPressed;

  /// The guidelines agreement: Submit stays disabled until it is ticked.
  final ValueListenable<bool>? agreed;

  /// Edit mode (Host Hub): "Save changes" for the step's section.
  final VoidCallback? onSave;

  /// An existing host: the last step reads "Save" (no review request) and
  /// needs no agreement tick.
  final bool savesInstead;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: p.bg),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12.ms),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.ms, 10.ms, 20.ms, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<HostIssue?>(
                valueListenable: notice,
                builder: (_, issue, _) => AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.bottomCenter,
                  child: issue == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: EdgeInsets.only(bottom: 10.ms),
                          child: Semantics(
                            liveRegion: true,
                            child: CText(
                              issue.key,
                              variables: issue.variables,
                              size: 14.5,
                              weight: FontWeight.w600,
                              color: p.danger,
                              align: TextAlign.center,
                            ),
                          ),
                        ),
                ),
              ),
              ListenableBuilder(
                listenable: Listenable.merge([step, busy, ?agreed]),
                builder: (_, _) {
                  final last = step.value == HostStep.guidelines;
                  final saves = last && savesInstead;
                  final blocked = last && !saves && agreed?.value == false;
                  final button = HostButton(
                    key: const ValueKey('hostflow-continue'),
                    label: saves
                        ? 'hostflow:edit.save_all'
                        : step.value.continueLabel,
                    arrow: !saves && step.value.continueArrow,
                    loading: busy.value,
                    onPressed: blocked ? null : onPressed,
                  );
                  final canSave =
                      onSave != null && hostSavableSteps.contains(step.value);
                  if (!canSave) return button;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      button,
                      Pressable(
                        key: const ValueKey('hostflow-save-section'),
                        onPressed: busy.value ? null : onSave,
                        child: Padding(
                          padding: EdgeInsets.only(top: 12.ms),
                          child: CText(
                            'hostflow:edit.save',
                            size: 15,
                            weight: FontWeight.w700,
                            color: HostPalette.of(context).accent,
                            align: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
