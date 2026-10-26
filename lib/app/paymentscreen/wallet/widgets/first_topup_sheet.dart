import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/first_topup_offer.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'offer_sheet.dart';

/// First-top-up offer for people who have never paid in (RN
/// `FirstTopupSheet`). Leads with what the money becomes rather than the
/// number asked for. The chosen amount, or null when dismissed.
Future<int?> showFirstTopupSheet(
  BuildContext context, {
  required double percent,
  required List<int> presets,
  required double voiceRate,
}) => showOfferSheet<int>(
  context,
  (_) => _FirstTopupSheet(
    percent: percent,
    options: FirstTopupOffer.options(presets),
    voiceRate: voiceRate,
  ),
);

class _FirstTopupSheet extends HookWidget {
  const _FirstTopupSheet({
    required this.percent,
    required this.options,
    required this.voiceRate,
  });

  final double percent;
  final List<int> options;

  /// Per-minute floor, for "about N minutes of talking".
  final double voiceRate;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final selected = useState<int?>(null);
    final chosen =
        selected.value ??
        (options.length > 1 ? options[1] : options.firstOrNull) ??
        0;
    final preview = BonusPreview.of(chosen, percent);
    final pct = WalletFormat.js(percent);
    final minutes = voiceRate > 0 ? (preview.total / voiceRate).floor() : 0;

    return OfferSheetFrame(
      children: [
        const OfferBadge(LucideIcons.sparkles),
        OfferHeading(
          title: 'payment:first_topup.title',
          subtitle: 'payment:first_topup.subtitle',
          variables: {'percent': pct},
        ),
        SizedBox(height: 18.ms),
        Row(
          children: [
            for (final (i, value) in options.indexed) ...[
              if (i > 0) SizedBox(width: 10.ms),
              Expanded(
                child: _Option(
                  amount: value,
                  bonus: BonusPreview.of(value, percent).bonus,
                  active: value == chosen,
                  onTap: () => selected.value = value,
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 14.ms),
        Container(
          padding: EdgeInsets.symmetric(vertical: 12.ms, horizontal: 14.ms),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.ms),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            children: [
              CText(
                'payment:first_topup.becomes',
                variables: {
                  'amount': WalletFormat.js(preview.amount),
                  'total': WalletFormat.js(preview.total),
                },
                size: 13.5,
                weight: FontWeight.w600,
                color: p.text,
                align: TextAlign.center,
              ),
              if (minutes > 0) ...[
                SizedBox(height: 3.ms),
                CText(
                  'payment:first_topup.minutes',
                  variables: {'minutes': '$minutes'},
                  size: 12,
                  color: p.muted,
                  align: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 16.ms),
        CButton(
          title: 'payment:offer.cta',
          titleVariables: {
            'amount': WalletFormat.js(preview.amount),
            'bonus': '${preview.bonus}',
          },
          showArrow: false,
          disabled: chosen <= 0,
          onPressed: () => Navigator.of(context).pop(chosen),
        ),
        SizedBox(height: 4.ms),
        CButton(
          title: 'payment:first_topup.not_now',
          variant: CButtonVariant.ghost,
          showArrow: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.amount,
    required this.bonus,
    required this.active,
    required this.onTap,
  });

  final int amount;
  final int bonus;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Pressable(
      onPressed: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 13.ms),
        decoration: BoxDecoration(
          color: active ? p.accent.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(14.ms),
          border: Border.all(
            color: active ? p.accent : p.cardBorder,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            CText.raw(
              '₹${WalletFormat.whole(amount)}',
              size: 16,
              weight: FontWeight.w700,
              color: p.text,
            ),
            SizedBox(height: 2.ms),
            CText.raw(
              '+₹$bonus',
              size: 12,
              weight: FontWeight.w700,
              color: WalletPalette.success,
            ),
          ],
        ),
      ),
    );
  }
}
