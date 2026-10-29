import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/me_palette.dart';

/// Small lime pill pinned to a row's top-right corner (RN `FloatingPill`):
/// springs in, then floats gently; static with "reduce motion". Never takes
/// touches. Wrap the row: `MeFloatingPill(pill: …, child: row)`.
class MeFloatingPill extends StatefulWidget {
  const MeFloatingPill({super.key, required this.pill, required this.child});

  /// The pill's label.
  final Widget pill;
  final Widget child;

  @override
  State<MeFloatingPill> createState() => _MeFloatingPillState();
}

class _MeFloatingPillState extends State<MeFloatingPill>
    with TickerProviderStateMixin {
  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 1.1,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.1,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
  ]).animate(_enter);
  late final Animation<Offset> _bob = Tween(
    begin: Offset.zero,
    end: const Offset(0, -0.18),
  ).chain(CurveTween(curve: Curves.easeInOutQuad)).animate(_float);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    HostEvents.unlockPromoShown();
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
      _float.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          top: -10.ms,
          right: 12.ms,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: SlideTransition(
                position: _bob,
                child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.ms,
                      vertical: 4.ms,
                    ),
                    decoration: BoxDecoration(
                      color: BrandColors.lime,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: widget.pill,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Become a Host" with the one-time "feature unlocked" celebration (RN
/// `HostUnlockRow`): pulsing glow border, bouncing gift icon, floating pill
/// and a dismissible bubble. Only the glow's opacity animates; the row itself
/// never scales (a full-width row would run past the screen edges).
class MeHostUnlockRow extends StatefulWidget {
  const MeHostUnlockRow({
    super.key,
    required this.rowBuilder,
    required this.onDismiss,
  });

  /// The normal menu row, given the icon to show (inside the row's tile).
  final Widget Function(Widget leading) rowBuilder;
  final VoidCallback onDismiss;

  @override
  State<MeHostUnlockRow> createState() => _MeHostUnlockRowState();
}

class _MeHostUnlockRowState extends State<MeHostUnlockRow>
    with TickerProviderStateMixin {
  late final _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
    upperBound: 0.95,
  );
  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _bubble = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
  );
  late final Animation<Offset> _iconBounce = TweenSequence([
    TweenSequenceItem(
      tween: Tween(begin: Offset.zero, end: const Offset(0, -0.3)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: const Offset(0, -0.3),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 70,
    ),
  ]).animate(_enter);
  late final Animation<Offset> _bubbleSlide = Tween(
    begin: const Offset(0, -0.05),
    end: Offset.zero,
  ).animate(_bubble);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _glow.value = 0.7;
      _enter.value = 1;
    } else {
      _enter.forward();
      _glow.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final tint = p.isDark
        ? BrandColors.limeA(0.14)
        : p.accent.withValues(alpha: 0.08);
    final edge = p.isDark
        ? BrandColors.limeA(0.35)
        : p.accent.withValues(alpha: 0.25);
    final radius = BorderRadius.circular(22.ms);
    final icon = SlideTransition(
      position: _iconBounce,
      child: Icon(LucideIcons.gift, size: 20.ms, color: p.accent),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MeFloatingPill(
          pill: const CText(
            'client:me.unlock.pill',
            size: 9,
            weight: FontWeight.w900,
            letterSpacing: 0.8,
            color: AppColors.black,
            maxLines: 1,
          ),
          child: Stack(
            children: [
              widget.rowBuilder(icon),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: FadeTransition(
                      opacity: _glow,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          // Flat: the pulsing border is the glow.
                          border: Border.all(color: p.accent, width: 2.ms),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10.ms),
        FadeTransition(
          opacity: _bubble,
          child: SlideTransition(
            position: _bubbleSlide,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The little arrow pointing up at the row.
                Positioned(
                  top: -6.ms,
                  left: 30.ms,
                  child: Transform.rotate(
                    angle: 0.785398, // 45°
                    child: Container(
                      width: 12.ms,
                      height: 12.ms,
                      decoration: BoxDecoration(
                        color: tint,
                        border: Border(
                          left: BorderSide(color: edge),
                          top: BorderSide(color: edge),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(14.ms),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(18.ms),
                    border: Border.all(color: edge),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.partyPopper,
                        size: 20.ms,
                        color: p.accent,
                      ),
                      SizedBox(width: 10.ms),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CText(
                              'client:me.unlock.title',
                              size: 13,
                              weight: FontWeight.w900,
                              color: p.text,
                            ),
                            SizedBox(height: 3.ms),
                            CText(
                              'client:me.unlock.body',
                              size: 12,
                              height: 17,
                              weight: FontWeight.w600,
                              color: p.isDark
                                  ? AppColors.whiteA(0.75)
                                  : AppColors.blackA(0.65),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 6.ms),
                      Pressable(
                        onPressed: () {
                          HostEvents.unlockPromoDismissed();
                          widget.onDismiss();
                        },
                        semanticLabel: context.t('client:me.unlock.dismiss'),
                        hitPadding: const EdgeInsets.all(10),
                        child: Icon(
                          LucideIcons.x,
                          size: 16.ms,
                          color: p.isDark
                              ? AppColors.whiteA(0.6)
                              : AppColors.blackA(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
