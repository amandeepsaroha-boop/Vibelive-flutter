import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/draft_controller.dart';
import '../helper/host_palette.dart';
import '../widgets/continue_bar.dart';
import '../widgets/sheet_frame.dart';
import '../widgets/step_body.dart';

/// 10 of 11: the community guidelines (Do / Don't) and the agreement;
/// "Submit for review" stays disabled until the box is ticked.
class GuidelinesStep extends StatelessWidget {
  const GuidelinesStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) => HostStepBody(
    title: 'hostflow:guidelines.title',
    subtitle: 'hostflow:guidelines.subtitle',
    children: [
      const HostGuidelines(),
      SizedBox(height: 18.ms),
      _Agree(agreed: draft.agreed),
    ],
  );
}

/// Do (green) and Don't (red), one card each.
class HostGuidelines extends StatelessWidget {
  const HostGuidelines({super.key});

  static const dos = ['do1', 'do2', 'do3', 'do4'];
  static const donts = ['dont1', 'dont2', 'dont3', 'dont4'];

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RuleBox(
          title: 'hostflow:review.do',
          keys: dos,
          icon: LucideIcons.circleCheck,
          bullet: LucideIcons.check,
          color: p.success,
          bg: p.successTint,
        ),
        SizedBox(height: 12.ms),
        _RuleBox(
          title: 'hostflow:review.dont',
          keys: donts,
          icon: LucideIcons.shieldX,
          bullet: LucideIcons.x,
          color: p.danger,
          bg: p.dangerTint,
        ),
      ],
    );
  }
}

class _RuleBox extends StatelessWidget {
  const _RuleBox({
    required this.title,
    required this.keys,
    required this.icon,
    required this.bullet,
    required this.color,
    required this.bg,
  });

  final String title;
  final List<String> keys;
  final IconData icon;
  final IconData bullet;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      padding: EdgeInsets.all(16.ms),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.ms),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20.ms, color: color),
              SizedBox(width: 8.ms),
              CText(title, size: 16, weight: FontWeight.w800, color: color),
            ],
          ),
          for (final k in keys)
            Padding(
              padding: EdgeInsets.only(top: 10.ms),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 2.ms),
                    child: Icon(bullet, size: 15.ms, color: color),
                  ),
                  SizedBox(width: 8.ms),
                  Expanded(
                    child: CText(
                      'hostflow:review.$k',
                      size: 14.5,
                      height: 20,
                      weight: FontWeight.w500,
                      color: p.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Agree extends StatelessWidget {
  const _Agree({required this.agreed});
  final ValueNotifier<bool> agreed;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: agreed,
      builder: (_, on, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            checked: on,
            label: context.t('hostflow:review.agree_label'),
            child: Pressable(
              key: const ValueKey('hostflow-agree'),
              onPressed: () {
                agreed.value = !on;
                HostEvents.guidelinesAgreed(agreed: !on);
              },
              hitPadding: EdgeInsets.all(6.ms),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24.ms,
                height: 24.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? p.accent : null,
                  borderRadius: BorderRadius.circular(7.ms),
                  border: on
                      ? null
                      : Border.all(color: p.fieldBorder, width: 1.5),
                ),
                child: on
                    ? Icon(LucideIcons.check, size: 16.ms, color: p.onAccent)
                    : null,
              ),
            ),
          ),
          SizedBox(width: 10.ms),
          Expanded(
            child: Pressable(
              key: const ValueKey('hostflow-guidelines-link'),
              onPressed: () {
                HostEvents.guidelinesOpened();
                showHostGuidelinesSheet(context);
              },
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: context.t('hostflow:review.agree_prefix')),
                    TextSpan(
                      text: context.t('hostflow:review.agree_link'),
                      style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: p.accent,
                      ),
                    ),
                  ],
                ),
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: p.text,
                  fontSize: 14.ms,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full Host Guidelines and Community Standards.
Future<void> showHostGuidelinesSheet(BuildContext context) =>
    showHostSheet<void>(
      context,
      title: 'hostflow:review.agree_link',
      name: 'host_guidelines_sheet',
      child: Builder(
        builder: (sheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 8.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CText(
                'hostflow:review.guidelines_body',
                size: 14.5,
                height: 21,
                weight: FontWeight.w500,
                color: HostPalette.of(sheet).text,
              ),
              SizedBox(height: 14.ms),
              const HostGuidelines(),
              SizedBox(height: 16.ms),
              HostButton(
                label: 'hostflow:rates.got_it',
                arrow: false,
                onPressed: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        ),
      ),
    );
