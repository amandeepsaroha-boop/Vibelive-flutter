import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../helper/balance_gate.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'offer_sheet.dart';

/// Shown when the wallet is short of what a call needs (RN
/// `BalanceGateSheet`). Replaces a cold "Insufficient Balance" alert whose
/// main button was Cancel: it shows progress, the gap, and the one tap that
/// closes it. Null when closed.
Future<BalanceGateAction?> showBalanceGateSheet(
  BuildContext context, {
  required BalanceGate gate,
  String? hostName,
}) => showOfferSheet<BalanceGateAction>(
  context,
  (_) => _BalanceGateSheet(gate: gate, hostName: hostName),
);

class _BalanceGateSheet extends StatelessWidget {
  const _BalanceGateSheet({required this.gate, this.hostName});

  final BalanceGate gate;
  final String? hostName;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final name = (hostName ?? '').trim();
    final earnings = gate.earnings.toStringAsFixed(0);
    return OfferSheetFrame(
      children: [
        SizedBox(height: 4.ms),
        // The headline is progress, not a refusal.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            CText.raw(
              '₹${WalletFormat.money(gate.balance)}',
              size: 30,
              weight: FontWeight.w800,
              color: p.text,
            ),
            SizedBox(width: 6.ms),
            CText(
              'payment:balance_gate.of',
              variables: {'required': WalletFormat.money(gate.required)},
              size: 17,
              weight: FontWeight.w600,
              color: p.muted,
            ),
          ],
        ),
        SizedBox(height: 14.ms),
        _ProgressBar(percent: gate.progressPercent),
        SizedBox(height: 14.ms),
        CText(
          name.isEmpty
              ? 'payment:balance_gate.caption'
              : 'payment:balance_gate.caption_host',
          variables: {'gap': WalletFormat.money(gate.gap), 'name': name},
          size: 14.5,
          weight: FontWeight.w600,
          color: p.muted,
          align: TextAlign.center,
        ),
        if (gate.minutes > 0 && gate.rate > 0) ...[
          SizedBox(height: 5.ms),
          CText(
            'payment:balance_gate.minutes',
            variables: {
              'minutes': WalletFormat.js(gate.minutes),
              'rate': WalletFormat.js(gate.rate),
            },
            size: 12.5,
            color: p.muted,
            align: TextAlign.center,
          ),
        ],
        SizedBox(height: 18.ms),
        CButton(
          title: 'payment:balance_gate.add',
          titleVariables: {'amount': '${gate.suggestedAmount}'},
          onPressed: () =>
              Navigator.of(context).pop(BalanceGateAction.addMoney),
        ),
        if (gate.liftedToMinimum) ...[
          SizedBox(height: 8.ms),
          CText(
            'payment:balance_gate.minimum_note',
            variables: {'amount': '${gate.suggestedAmount}'},
            size: 11.5,
            color: p.muted,
            align: TextAlign.center,
          ),
        ],
        if (gate.hasEarnings) ...[
          SizedBox(height: 10.ms),
          CButton(
            title: gate.earningsCoversGap
                ? 'payment:balance_gate.use_earnings'
                : 'payment:balance_gate.transfer_earnings',
            titleVariables: {'amount': earnings},
            variant: CButtonVariant.outline,
            showArrow: false,
            onPressed: () =>
                Navigator.of(context).pop(BalanceGateAction.transferEarnings),
          ),
        ],
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4.ms),
      child: Container(
        height: 7.ms,
        color: p.inputBorder,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: percent / 100),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          builder: (_, value, _) => FractionallySizedBox(
            widthFactor: value,
            heightFactor: 1,
            child: ColoredBox(color: p.accent),
          ),
        ),
      ),
    );
  }
}
