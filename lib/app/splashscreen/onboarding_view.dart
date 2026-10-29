import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../core/analytics/events/auth_events.dart';
import '../../core/analytics/screen_tracker.dart';
import '../../core/utils/scale.dart';
import '../component/app_logo.dart';
import 'launch_logo.dart';
import '../component/c_button.dart';
import '../component/c_text.dart';
import 'onboarding_visuals.dart';
import 'splash_palette.dart';

/// What the app is, in three slides (RN onboarding stage). Swipe or tap
/// through; SKIP / GET STARTED leave once the startup route is known.
class OnboardingView extends HookWidget {
  const OnboardingView({
    super.key,
    required this.ready,
    required this.onFinish,
  });

  /// Startup route resolved; until then the last slide shows PREPARING….
  final bool ready;
  final VoidCallback onFinish;

  static const _slides = ['talk', 'pay', 'choose'];

  @override
  Widget build(BuildContext context) {
    final palette = SplashPalette.of(context);
    final index = useState(0);
    final dragDx = useRef(0.0);
    final i = index.value;
    final isLast = i == _slides.length - 1;
    final insets = MediaQuery.paddingOf(context);
    final ctaBottom = math.max(20.ms, insets.bottom + 6.ms);
    // Dots (6) + gap (14) + CTA (76) above [ctaBottom]; the slide ends 8
    // above that, or at RN's 128 when the home indicator leaves room.
    final slideBottom = math.max(128.ms, ctaBottom + 104.ms);

    useEffect(() {
      AuthEvents.introStarted();
      return null;
    }, const []);
    // Each slide is a screen.
    useEffect(() {
      ScreenTracker.view('intro_${_slides[i]}');
      AuthEvents.introSlideViewed(index: i, slide: _slides[i]);
      return null;
    }, [i]);

    void show(int to) => index.value = to.clamp(0, _slides.length - 1);
    void next() {
      if (!isLast) {
        show(i + 1);
      } else if (ready) {
        AuthEvents.introCompleted(slides: _slides.length);
        onFinish();
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => dragDx.value = 0,
      onHorizontalDragUpdate: (d) => dragDx.value += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final dx = dragDx.value, vx = d.primaryVelocity ?? 0;
        if (dx < -50 || vx < -500) {
          if (!isLast) show(i + 1);
        } else if (dx > 50 || vx > 500) {
          show(i - 1);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 280.ms,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [palette.glow, palette.glowEnd],
                ),
              ),
            ),
          ),
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  34.ms,
                  math.max(52.ms, insets.top + 8.ms),
                  34.ms,
                  0,
                ),
                child: _Progress(index: i, count: _slides.length),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 28.ms),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    LaunchLogoAnchor(child: AppLogo(size: 120.ms)),
                    CButton(
                      title: 'splash:skip',
                      variant: CButtonVariant.ghost,
                      showArrow: false,
                      titleColor: palette.text,
                      onPressed: () {
                        AuthEvents.introSkipped(index: i, slide: _slides[i]);
                        ready ? onFinish() : show(_slides.length - 1);
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(28.ms, 0, 28.ms, slideBottom),
                  // Short phones shrink the slide instead of overflowing.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: MediaQuery.sizeOf(context).width - 56.ms,
                      child: _Slide(key: ValueKey(i), id: _slides[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 28.ms,
            right: 28.ms,
            bottom: ctaBottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dots(index: i, count: _slides.length),
                SizedBox(height: 14.ms),
                CButton(
                  title: !isLast
                      ? 'splash:continue'
                      : ready
                      ? 'splash:get_started'
                      : 'splash:preparing',
                  variant: CButtonVariant.cta,
                  color: palette.ctaBg,
                  titleColor: palette.ctaText,
                  disabled: isLast && !ready,
                  onPressed: next,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One slide. A new key per index replays the fade + rise (RN `slideIn`).
class _Slide extends StatelessWidget {
  const _Slide({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final palette = SplashPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 560),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 36.ms * (1 - v)),
          child: child,
        ),
      ),
      // Painted once: each frame of the rise only moves this layer.
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 320.ms),
              child: CText(
                'splash:slides.$id.title',
                variant: CTextVariant.h1,
                italic: true,
                color: palette.text,
              ),
            ),
            SizedBox(height: 12.ms),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 290.ms),
              child: CText(
                'splash:slides.$id.desc',
                size: 18,
                height: 24,
                weight: FontWeight.w700,
                color: palette.desc,
              ),
            ),
            SizedBox(height: 36.ms),
            SizedBox(
              width: double.infinity,
              height: 280.ms,
              child: Center(
                child: switch (id) {
                  'talk' => const InterestVisual(),
                  'pay' => const PayVisual(),
                  _ => const LiveVisual(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lime segment sliding along a hairline track.
class _Progress extends StatelessWidget {
  const _Progress({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = SplashPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 2.ms,
        child: ColoredBox(
          color: palette.progressTrack,
          child: AnimatedAlign(
            alignment: Alignment(-1 + 2 * index / (count - 1), 0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 1 / count,
              heightFactor: 1,
              child: ColoredBox(color: palette.accent),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = SplashPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var d = 0; d < count; d++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.symmetric(horizontal: 4.ms),
            width: d == index ? 22.ms : 6.ms,
            height: 6.ms,
            decoration: BoxDecoration(
              color: d == index ? palette.accent : palette.dot,
              borderRadius: BorderRadius.circular(999),
              boxShadow: d == index
                  ? [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.8),
                        blurRadius: 6.ms,
                      ),
                    ]
                  : null,
            ),
          ),
      ],
    );
  }
}
