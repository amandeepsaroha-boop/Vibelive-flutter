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
/// backend once the payment settles; nothing is promised here it would not
/// honour.
Future<bool> showAbandonOfferSheet(
  BuildContext context, {
  required BonusPreview offer,
  required double percent,
  required double windowMinutes,
}) async =>
    await showOfferSheet<bool>(
      context,
      (_) => _AbandonOfferSheet(
        offer: offer,
        percent: percent,
        windowMinutes: windowMinutes,
      ),
    ) ??
    false;

class _AbandonOfferSheet extends HookWidget {
  const _AbandonOfferSheet({
    required this.offer,
    required this.percent,
    required this.windowMinutes,
  });

  final BonusPreview offer;
  final double percent;
  final double windowMinutes;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final total = windowMinutes > 0 ? (windowMinutes * 60).round() : 0;
    final left = useState(total);
    // A stated deadline has to actually tick, or it reads as a gimmick.
    useEffect(() {
      if (total <= 0) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (left.value <= 0) return t.cancel();
        left.value = left.value - 1;
      });
      return timer.cancel;
    }, [total]);
    final mmss =
        '${left.value ~/ 60}:${(left.value % 60).toString().padLeft(2, '0')}';
    final amount = WalletFormat.js(offer.amount);

    Widget row(String label, String value, Color color, {bool bold = false}) =>
        Row(
          children: [
            Expanded(
              child: CText(
                label,
                size: bold ? 14 : 13,
                weight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
            CText.raw(
              value,
              size: bold ? 15 : 13,
              weight: bold ? FontWeight.w800 : FontWeight.w700,
              color: color,
            ),
          ],
        );

    return OfferSheetFrame(
      children: [
        const OfferBadge(LucideIcons.gift),
        OfferHeading(
          title: 'payment:abandon_offer.title',
          subtitle: 'payment:abandon_offer.subtitle',
          variables: {'percent': WalletFormat.js(percent)},
        ),
        SizedBox(height: 16.ms),
        Container(
          padding: EdgeInsets.all(14.ms),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.ms),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            children: [
              row('payment:abandon_offer.you_add', '₹$amount', p.muted),
              SizedBox(height: 8.ms),
              row(
                'payment:abandon_offer.bonus',
                '+₹${offer.bonus}',
                WalletPalette.success,
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10.ms),
                child: Container(height: 1, color: p.cardBorder),
              ),
              row(
                'payment:abandon_offer.balance',
                '₹${WalletFormat.js(offer.total)}',
                p.text,
                bold: true,
              ),
            ],
          ),
        ),
        if (total > 0) ...[
          SizedBox(height: 12.ms),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.clock, size: 13.ms, color: p.muted),
              SizedBox(width: 6.ms),
              CText(
                'payment:abandon_offer.ends_in',
                variables: {'time': mmss},
                size: 12,
                weight: FontWeight.w600,
                color: p.muted,
              ),
            ],
          ),
        ],
        SizedBox(height: 16.ms),
        CButton(
          title: 'payment:offer.cta',
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
    );
  }
}
