import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../helper/first_topup_offer.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'offer_sheet.dart';

/// Exit-intent offer, right after someone closes checkout unpaid (RN
/// `AbandonOfferSheet`). True when accepted. The bonus is granted by the
/// backend once the payment settles; once the window has run out this says
/// so instead of promising it.
Future<bool> showAbandonOfferSheet(
  BuildContext context, {
  required BonusPreview offer,
  required double percent,
  required double windowMinutes,
  required double gstPercent,
}) async =>
    await showOfferSheet<bool>(
      context,
      (_) => _AbandonOfferSheet(
        offer: offer,
        percent: percent,
        windowMinutes: windowMinutes,
        gstPercent: gstPercent,
      ),
      name: 'abandon_offer_sheet',
    ) ??
    false;

/// Light by design: one entrance controller (fade / slide transitions, no
/// rebuilds), one breathing ring and one draining bar on the compositor,
/// and a once-a-second notifier that rebuilds only the "ends in" text. The
/// sheet itself rebuilds once, when the offer expires.
class _AbandonOfferSheet extends HookWidget {
  const _AbandonOfferSheet({
    required this.offer,
    required this.percent,
    required this.windowMinutes,
    required this.gstPercent,
  });

  final BonusPreview offer;
  final double percent;
  final double windowMinutes;
  final double gstPercent;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final window = windowMinutes > 0 ? (windowMinutes * 60).round() : 0;

    final enter = useAnimationController(
      duration: const Duration(milliseconds: 520),
    );
    final drain = useAnimationController(duration: Duration(seconds: window));
    final left = useValueNotifier(window);
    final expired = useState(false);
    useEffect(() {
      if (still) {
        enter.value = 1;
      } else {
        enter.forward();
      }
      if (window <= 0) return null;
      // A stated deadline has to actually tick, or it reads as a gimmick.
      drain.forward();
      final timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (left.value <= 1) {
          t.cancel();
          left.value = 0;
          expired.value = true;
          return;
        }
        left.value--;
      });
      return timer.cancel;
    }, const []);

    final amount = WalletFormat.js(offer.amount);
    // The real amount; GST is separate, added at checkout.
    final pay = offer.amount;
    final live = !expired.value;

    // Staggered in: each block fades and rises a little after the last.
    Widget step(int i, Widget child) {
      final start = (i * 0.12).clamp(0.0, 0.6);
      final curve = CurvedAnimation(
        parent: enter,
        curve: Interval(
          start,
          (start + 0.55).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic,
        ),
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    }

    return OfferSheetFrame(
      children: [
        step(0, _GiftBadge(enter: enter, still: still)),
        SizedBox(height: 14.ms),
        step(
          1,
          Column(
            children: [
              CText(
                live
                    ? 'payment:abandon_offer.title'
                    : 'payment:abandon_offer.expired_title',
                size: 22,
                weight: FontWeight.w900,
                letterSpacing: -0.4,
                align: TextAlign.center,
                color: p.text,
              ),
              SizedBox(height: 6.ms),
              CText(
                live
                    ? 'payment:abandon_offer.subtitle'
                    : 'payment:abandon_offer.expired_subtitle',
                variables: {'percent': WalletFormat.js(percent)},
                size: 13.5,
                weight: FontWeight.w500,
                height: 19,
                align: TextAlign.center,
                color: p.muted,
              ),
            ],
          ),
        ),
        SizedBox(height: 18.ms),
        step(
          2,
          _OfferCard(
            live: live,
            bonus: offer.bonus,
            amount: amount,
            pay: _money(pay),
            get: WalletFormat.js(live ? offer.total : offer.amount),
          ),
        ),
        if (window > 0 && live) ...[
          SizedBox(height: 14.ms),
          step(3, _Countdown(left: left, drain: drain)),
        ],
        SizedBox(height: 18.ms),
        step(
          4,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CButton(
                title: live
                    ? 'payment:abandon_offer.cta'
                    : 'payment:abandon_offer.cta_plain',
                titleVariables: {'amount': amount, 'bonus': '${offer.bonus}'},
                showArrow: false,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              SizedBox(height: 4.ms),
              CButton(
                title: 'payment:abandon_offer.later',
                variant: CButtonVariant.ghost,
                showArrow: false,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `118` / `59.50`: whole rupees when it is whole.
String _money(double v) =>
    v == v.roundToDouble() ? WalletFormat.whole(v) : v.toStringAsFixed(2);

/// Gift in a gradient circle: pops in, then a soft ring breathes behind it.
class _GiftBadge extends HookWidget {
  const _GiftBadge({required this.enter, required this.still});

  final Animation<double> enter;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final ring = useAnimationController(
      duration: const Duration(milliseconds: 1600),
    );
    useEffect(() {
      if (!still) ring.repeat();
      return null;
    }, const []);
    final pop = CurvedAnimation(
      parent: enter,
      curve: const Interval(0, 0.7, curve: Curves.elasticOut),
    );
    final size = 64.ms;
    return Center(
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size * 1.6,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!still)
                FadeTransition(
                  opacity: Tween(begin: 0.5, end: 0.0).animate(ring),
                  child: ScaleTransition(
                    scale: Tween(begin: 1.0, end: 1.55).animate(
                      CurvedAnimation(parent: ring, curve: Curves.easeOut),
                    ),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.accent.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ScaleTransition(
                scale: pop,
                child: Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: p.accentGradient,
                    ),
                  ),
                  child: Icon(LucideIcons.gift, size: 30.ms, color: p.onAccent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The value at a glance: "+₹20 FREE", then what is paid and what lands.
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.live,
    required this.bonus,
    required this.amount,
    required this.pay,
    required this.get,
  });

  final bool live;
  final int bonus;
  final String amount;
  final String pay;
  final String get;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(18.ms, 16.ms, 18.ms, 14.ms),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.ms),
        gradient: live
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: p.accentGradient,
              )
            : null,
        color: live ? null : p.cardBg,
        border: live ? null : Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          if (live) ...[
            CText(
              'payment:abandon_offer.free',
              variables: {'bonus': '$bonus'},
              size: 30,
              weight: FontWeight.w900,
              letterSpacing: -0.6,
              color: p.onAccent,
            ),
            CText(
              'payment:abandon_offer.on_topup',
              variables: {'amount': amount},
              size: 12.5,
              weight: FontWeight.w600,
              color: p.onAccent.withValues(alpha: 0.8),
            ),
            SizedBox(height: 14.ms),
          ],
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.ms, horizontal: 6.ms),
            decoration: BoxDecoration(
              color: live ? p.onAccent.withValues(alpha: 0.12) : p.inputBg,
              borderRadius: BorderRadius.circular(14.ms),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'payment:abandon_offer.you_pay',
                      value: '₹$pay',
                      light: live,
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: live
                        ? p.onAccent.withValues(alpha: 0.25)
                        : p.cardBorder,
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'payment:abandon_offer.wallet_gets',
                      value: '₹$get',
                      hint: live ? 'payment:abandon_offer.incl_bonus' : null,
                      light: live,
                      strong: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.light,
    this.hint,
    this.strong = false,
  });

  final String label;
  final String value;
  final String? hint;
  final bool light;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    // `light`: on the accent card, so on-accent ink.
    final main = light ? p.onAccent : p.text;
    final soft = light ? p.onAccent.withValues(alpha: 0.75) : p.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CText(
          label,
          size: 10,
          weight: FontWeight.w800,
          letterSpacing: 0.8,
          color: soft,
          maxLines: 1,
        ),
        SizedBox(height: 2.ms),
        CText.raw(
          value,
          size: strong ? 20 : 18,
          weight: FontWeight.w900,
          color: main,
          maxLines: 1,
        ),
        if (hint != null)
          CText(hint!, size: 10, weight: FontWeight.w600, color: soft),
      ],
    );
  }
}

/// "Offer ends in 9:59" over a bar that drains to the deadline. The bar is
/// a transform on the compositor; only the text rebuilds, once a second.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.left, required this.drain});

  final ValueNotifier<int> left;
  final Animation<double> drain;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return RepaintBoundary(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.clock, size: 13.ms, color: p.accent),
              SizedBox(width: 6.ms),
              ValueListenableBuilder<int>(
                valueListenable: left,
                builder: (_, s, _) => CText(
                  'payment:abandon_offer.ends_in',
                  variables: {
                    'time': '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
                  },
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: p.text,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.ms),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4.ms,
              child: ColoredBox(
                color: p.accent.withValues(alpha: 0.12),
                child: AnimatedBuilder(
                  animation: drain,
                  builder: (_, child) => Transform(
                    alignment: Alignment.centerLeft,
                    transform: Matrix4.diagonal3Values(1 - drain.value, 1, 1),
                    child: child,
                  ),
                  child: ColoredBox(
                    color: p.accent,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
