import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/client/referral_api.dart';
import '../../../authscreen/helper/link_parser.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/me_actions.dart';
import '../helper/me_palette.dart';
import 'me_rows.dart';

/// "Invite & Earn" (RN `ReferralInviteCard`): the code with COPY, WhatsApp,
/// Invite All, and a link to the referral screen. Every action shares the
/// invite link (`?r=i`) and counts as an invite share. Hidden without a code
/// (a failed read is silent by design).
class MeReferralInviteCard extends HookWidget {
  const MeReferralInviteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final code = useReferralCode(context).data ?? '';
    final track = useTrackReferralShare(type: ReferralShareType.invite);
    final copied = useState(false);
    useEffect(() {
      if (!copied.value) return null;
      final t = Timer(
        const Duration(milliseconds: 1800),
        () => copied.value = false,
      );
      return t.cancel;
    }, [copied.value]);

    if (code.isEmpty) return const SizedBox.shrink();

    final p = MePalette.of(context);
    final link = LinkParser.shareLink(code, ReferralIntent.invite);
    final message = context.t(
      'client:me.invite.message',
      variables: {'code': code, 'link': link},
    );
    // Counting is best effort: it never blocks or fails a share.
    void count() => track.mutate(code).ignore();

    Future<void> copy() async {
      await MeActions.copy(code);
      copied.value = true;
      count();
    }

    Future<void> inviteAll() async {
      count();
      await MeActions.share(message);
    }

    Future<void> whatsApp() async {
      count();
      if (!await MeActions.openWhatsApp(message)) {
        await MeActions.share(message);
      }
    }

    return Container(
      margin: EdgeInsets.only(top: 14.ms),
      padding: EdgeInsets.all(18.ms),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(28.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MeIconBox(
                color: p.accent,
                icon: LucideIcons.gift,
                size: 40,
                radius: 14,
                iconSize: 20,
                alpha: 0x24,
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CText(
                      'client:me.invite.title',
                      size: 15,
                      weight: FontWeight.w900,
                      color: p.text,
                    ),
                    SizedBox(height: 2.ms),
                    CText(
                      'client:me.invite.subtitle',
                      size: 11,
                      weight: FontWeight.w600,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14.ms),
          Pressable(
            activeOpacity: 0.8,
            onPressed: copy,
            child: CustomPaint(
              painter: _DashedBorder(p.accent.withValues(alpha: 0.45), 16.ms),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.ms,
                  vertical: 12.ms,
                ),
                decoration: BoxDecoration(
                  color: p.isDark
                      ? AppColors.whiteA(0.04)
                      : AppColors.blackA(0.03),
                  borderRadius: BorderRadius.circular(16.ms),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CText(
                            'client:me.invite.your_code',
                            size: 9,
                            weight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: p.muted,
                          ),
                          SizedBox(height: 2.ms),
                          CText.raw(
                            code,
                            size: 20,
                            weight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: p.text,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    Icon(LucideIcons.copy, size: 15.ms, color: p.accent),
                    SizedBox(width: 6.ms),
                    CText(
                      copied.value
                          ? 'client:me.invite.copied'
                          : 'client:me.invite.copy',
                      size: 11,
                      weight: FontWeight.w800,
                      letterSpacing: 1,
                      color: p.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 12.ms),
          Row(
            children: [
              Expanded(
                child: _ShareButton(
                  color: BrandColors.whatsapp,
                  fg: AppColors.white,
                  icon: SvgPicture.string(
                    _whatsAppSvg,
                    width: 19.ms,
                    height: 19.ms,
                    colorFilter: const ColorFilter.mode(
                      AppColors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                  label: 'client:me.invite.whatsapp',
                  onTap: whatsApp,
                ),
              ),
              SizedBox(width: 10.ms),
              Expanded(
                child: _ShareButton(
                  color: p.accent,
                  fg: p.onAccent,
                  icon: Icon(
                    LucideIcons.userPlus,
                    size: 18.ms,
                    color: p.onAccent,
                  ),
                  label: 'client:me.invite.invite_all',
                  onTap: inviteAll,
                ),
              ),
            ],
          ),
          SizedBox(height: 4.ms),
          Pressable(
            activeOpacity: 0.8,
            onPressed: () => MeActions.open(context, AppRoutes.referral),
            child: Padding(
              padding: EdgeInsets.only(top: 10.ms),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: CText(
                      'client:me.invite.activity',
                      size: 12,
                      weight: FontWeight.w800,
                      color: p.muted,
                      maxLines: 1,
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 16.ms, color: p.muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.color,
    required this.fg,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final Color fg;
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    activeOpacity: 0.85,
    onPressed: onTap,
    child: Container(
      height: 48.ms,
      padding: EdgeInsets.symmetric(horizontal: 8.ms),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16.ms),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          SizedBox(width: 8.ms),
          Flexible(
            child: CText(
              label,
              size: 12,
              weight: FontWeight.w900,
              letterSpacing: 1,
              color: fg,
              maxLines: 1,
            ),
          ),
        ],
      ),
    ),
  );
}

/// RN `borderStyle: 'dashed'` around the code.
class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 4.0, gap = 3.0;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

/// Font Awesome "whatsapp" (brands, CC BY 4.0).
const _whatsAppSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path d="'
    'M380.9 97.1C339 55.1 283.2 32 223.9 32c-122.4 0-222 99.6-222 222 0 39.1 '
    '10.2 77.3 29.6 111L0 480l117.7-30.9c32.4 17.7 68.9 27 106.1 27h.1c122.3 '
    '0 224.1-99.6 224.1-222 0-59.3-25.2-115-67.1-157zm-157 341.6c-33.2 '
    '0-65.7-8.9-94-25.7l-6.7-4-69.8 18.3L72 359.2l-4.4-7c-18.5-29.4-28.2-63.3'
    '-28.2-98.2 0-101.7 82.8-184.5 184.6-184.5 49.3 0 95.6 19.2 130.4 54.1 '
    '34.8 34.9 56.2 81.2 56.1 130.5 0 101.8-84.9 184.6-186.6 184.6zm101.2'
    '-138.2c-5.5-2.8-32.8-16.2-37.9-18-5.1-1.9-8.8-2.8-12.5 2.8-3.7 5.6-14.3 '
    '18-17.6 21.8-3.2 3.7-6.5 4.2-12 1.4-32.6-16.3-54-29.1-75.5-66-5.7-9.8 '
    '5.7-9.1 16.3-30.3 1.8-3.7.9-6.9-.5-9.7-1.4-2.8-12.5-30.1-17.1-41.2-4.5'
    '-10.8-9.1-9.3-12.5-9.5-3.2-.2-6.9-.2-10.6-.2-3.7 0-9.7 1.4-14.8 6.9-5.1 '
    '5.6-19.4 19-19.4 46.3 0 27.3 19.9 53.7 22.6 57.4 2.8 3.7 39.1 59.7 94.8 '
    '83.8 35.2 15.2 49 16.5 66.6 13.9 10.7-1.6 32.8-13.4 37.4-26.4 4.6-13 '
    '4.6-24.1 3.2-26.4-1.3-2.5-5-3.9-10.5-6.6z"/></svg>';
