import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/network/strapi.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import 'c_text.dart';
import 'pressable.dart';

bool _isInfluencer(JsonMap? u, JsonMap? e) =>
    J.boolean(u?['instaVerified']) ||
    J.boolean(e?['instaVerified']) ||
    J.boolean(u?['facebookVerified']) ||
    J.boolean(e?['facebookVerified']) ||
    J.boolean(u?['snapchatVerified']) ||
    J.boolean(e?['snapchatVerified']);

bool _isVerified(JsonMap? u, JsonMap? e) =>
    J.boolean(u?['verified']) ||
    J.boolean(e?['verified']) ||
    J.boolean(e?['isVerified']);

/// RN `VerificationBadge`: lime scalloped badge next to a name.
/// Influencers (insta/fb/snap verified) get a crown, verified users a check,
/// everyone else nothing.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({
    super.key,
    this.user,
    this.expert,
    this.size = 16,
    this.onProfilePage = false,
  });

  final JsonMap? user;
  final JsonMap? expert;
  final double size;
  final bool onProfilePage;

  @override
  Widget build(BuildContext context) {
    final influencer = _isInfluencer(user, expert);
    if (!influencer && !_isVerified(user, expert)) {
      return const SizedBox.shrink();
    }
    final glyphColor = influencer && onProfilePage && !context.colors.isDark
        ? AppColors.white
        : AppColors.black;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: const _DecagramPainter(BrandColors.lime),
        child: Center(
          child: Icon(
            influencer ? LucideIcons.crown : Icons.check_rounded,
            size: (size * (influencer ? 0.56 : 0.62)).roundToDouble(),
            color: glyphColor,
            weight: 800,
          ),
        ),
      ),
    );
  }
}

/// RN `InfluencerBadge`: accent pill with a crown and a shimmer sweep.
class InfluencerBadge extends StatefulWidget {
  const InfluencerBadge({super.key, this.size = 14, this.onPressed});

  final double size;
  final VoidCallback? onPressed;

  @override
  State<InfluencerBadge> createState() => _InfluencerBadgeState();
}

class _InfluencerBadgeState extends State<InfluencerBadge>
    with SingleTickerProviderStateMixin {
  // 1.2s sweep + 1.8s pause, looped (same timing as RN).
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.size;
    final badge = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: BoxConstraints(maxWidth: s * 8),
          padding: EdgeInsets.symmetric(
            horizontal: s * 0.5,
            vertical: s * 0.22,
          ),
          decoration: BoxDecoration(
            color: c.accent,
            border: Border.all(color: c.accent),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.crown, size: s * 0.8, color: c.inverse),
                  SizedBox(width: s * 0.2),
                  Flexible(
                    child: CText(
                      'badge.influencer',
                      size: s * 0.65,
                      weight: FontWeight.w900,
                      letterSpacing: 0.8,
                      uppercase: true,
                      color: c.inverse,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (_, _) {
                      final t = (_ctrl.value / 0.4).clamp(0.0, 1.0);
                      final dx = -s * 8 + (s * 18) * t;
                      return Transform.translate(
                        offset: Offset(dx, 0),
                        child: Transform(
                          transform: Matrix4.skewX(-0.35),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: s * 3,
                              color: AppColors.whiteA(0.28),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (widget.onPressed == null) return badge;
    return Pressable(
      onPressed: widget.onPressed,
      activeOpacity: 0.8,
      child: badge,
    );
  }
}

/// MDI "decagram": 10-point star with rounded tips.
class _DecagramPainter extends CustomPainter {
  const _DecagramPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2 * 0.9;
    final inner = outer * 0.8;
    final path = Path();
    for (var i = 0; i < 20; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 10;
      final p = center + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.shortestSide * 0.1;
    canvas
      ..drawPath(path, paint..style = PaintingStyle.fill)
      ..drawPath(path, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_DecagramPainter old) => old.color != color;
}
