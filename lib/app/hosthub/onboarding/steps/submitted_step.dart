import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../helper/host_palette.dart';
import '../widgets/step_body.dart';

/// 11 of 11: the request is in. A check that pops in once over static
/// confetti, then what happens next. Also the Approval Status screen while
/// pending, and (with [approvedSteps], all [done]) once approved.
class SubmittedStep extends StatelessWidget {
  const SubmittedStep({
    super.key,
    this.title = 'hostflow:submitted.title',
    this.body = 'hostflow:submitted.body',
    this.steps = pendingSteps,
    this.done = 1,
  });

  /// i18n keys.
  final String title;
  final String body;

  /// The timeline: `(title, body)` i18n keys per step.
  final List<(String, String)> steps;

  /// How many steps are checked; the next one is in progress.
  final int done;

  static const pendingSteps = [
    ('hostflow:submitted.s1_title', 'hostflow:submitted.s1_body'),
    ('hostflow:submitted.s2_title', 'hostflow:submitted.s2_body'),
    ('hostflow:submitted.s3_title', 'hostflow:submitted.s3_body'),
  ];

  static const approvedSteps = [
    ('hostflow:submitted.s1_title', 'hostflow:submitted.s1_body'),
    ('hostflow:submitted.s2_done_title', 'hostflow:submitted.s2_done_body'),
    (
      'hostflow:submitted.s3_approved_title',
      'hostflow:submitted.s3_approved_body',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24.ms, 8.ms, 24.ms, 24.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 170.ms,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _Confetti(p.accent),
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.6, end: 1),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    builder: (_, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: Container(
                      width: 96.ms,
                      height: 96.ms,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: p.gradient.reversed.toList(),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        LucideIcons.check,
                        size: 46.ms,
                        color: p.onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 18.ms),
          HostTitle(title, align: TextAlign.center),
          SizedBox(height: 10.ms),
          CText(
            body,
            size: 17,
            height: 24.5,
            weight: FontWeight.w500,
            color: p.muted,
            align: TextAlign.center,
          ),
          SizedBox(height: 26.ms),
          _Timeline(palette: p, steps: steps, done: done),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.palette,
    required this.steps,
    required this.done,
  });
  final HostPalette palette;
  final List<(String, String)> steps;
  final int done;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget dot(int i) => switch (i - done) {
      < 0 => Container(
        width: 40.ms,
        height: 40.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: p.buttonGradient,
        ),
        child: Icon(LucideIcons.check, size: 20.ms, color: p.onAccent),
      ),
      0 => Container(
        width: 40.ms,
        height: 40.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.card,
          border: Border.all(color: p.cardBorder, width: 1.5),
        ),
        child: Container(
          width: 14.ms,
          height: 14.ms,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: p.text, width: 1.6),
          ),
        ),
      ),
      _ => SizedBox(
        width: 40.ms,
        height: 40.ms,
        child: Icon(LucideIcons.bell, size: 24.ms, color: p.text),
      ),
    };

    return Column(
      children: [
        for (final (i, (title, body)) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    dot(i),
                    if (i < steps.length - 1)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: EdgeInsets.symmetric(vertical: 4.ms),
                          // Between two checked steps: the accent.
                          color: i + 1 < done ? p.accent : p.track,
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 14.ms),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 2.ms, bottom: 18.ms),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CText(
                          title,
                          size: 17,
                          weight: FontWeight.w700,
                          color: p.text,
                        ),
                        SizedBox(height: 3.ms),
                        CText(
                          body,
                          size: 14.5,
                          weight: FontWeight.w500,
                          color: p.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Fixed scatter of small rounded bits around the check.
class _Confetti extends CustomPainter {
  const _Confetti(this.accent);
  final Color accent;

  static const _bits = [
    (-0.36, -0.30, 0.6),
    (-0.42, 0.05, 1.2),
    (-0.30, 0.34, 2.1),
    (-0.22, -0.10, 0.2),
    (0.30, -0.36, 1.0),
    (0.40, -0.12, 2.6),
    (0.34, 0.22, 0.4),
    (0.24, 0.38, 1.7),
    (0.44, 0.10, 2.2),
    (-0.46, -0.20, 1.5),
    (0.16, -0.42, 0.9),
    (-0.12, 0.44, 2.8),
  ];

  static const _colors = [
    StatusColors.warningOrange,
    AiColors.pink,
    BrandColors.tealDark,
    AiColors.violet,
    StatusColors.info,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint();
    for (var i = 0; i < _bits.length; i++) {
      final (x, y, angle) = _bits[i];
      paint.color = i % 4 == 0 ? accent : _colors[i % _colors.length];
      canvas
        ..save()
        ..translate(c.dx + x * size.width, c.dy + y * size.height * 1.05)
        ..rotate(angle * math.pi / 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 10, height: 5),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti old) => old.accent != accent;
}
