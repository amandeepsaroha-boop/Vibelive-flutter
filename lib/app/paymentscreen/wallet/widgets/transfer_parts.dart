import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/wallet_amounts.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';

/// CASH → EARNINGS balance cards of the transfer sheet.
class TransferWallets extends StatelessWidget {
  const TransferWallets({
    super.key,
    required this.cash,
    required this.earnings,
  });

  final double cash;
  final double earnings;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    Widget card(String label, double amount) => Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.ms, horizontal: 12.ms),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(20.ms),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          children: [
            CText(
              label,
              size: 9,
              weight: FontWeight.w900,
              letterSpacing: 1.5,
              color: p.muted,
              maxLines: 1,
            ),
            SizedBox(height: 6.ms),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: CText.raw(
                '₹${WalletFormat.amount(amount)}',
                size: 18,
                weight: FontWeight.w900,
                color: p.text,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );

    return Row(
      children: [
        card('payment:transfer.cash', cash),
        SizedBox(width: 10.ms),
        // RN arrowWrapper: a bare 32 box with the arrow; no fill, no ring.
        SizedBox.square(
          dimension: 32.ms,
          child: Center(
            child: Icon(LucideIcons.arrowRight, size: 18.ms, color: p.accent),
          ),
        ),
        SizedBox(width: 10.ms),
        card('payment:transfer.earnings', earnings),
      ],
    );
  }
}

/// AMOUNT TO TRANSFER / MAX, the preset-filled amount box (not editable, as
/// in RN) and the 25–100% chips.
class TransferAmountBox extends StatelessWidget {
  const TransferAmountBox({
    super.key,
    required this.quote,
    required this.selectedPreset,
    required this.onMax,
    required this.onPreset,
  });

  final TransferQuote quote;
  final int? selectedPreset;
  final VoidCallback onMax;
  final ValueChanged<int> onPreset;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CText(
                'payment:transfer.amount_label',
                size: 10,
                weight: FontWeight.w900,
                letterSpacing: 2,
                color: p.muted,
                maxLines: 1,
              ),
            ),
            CText(
              'payment:transfer.max_label',
              variables: {'amount': WalletFormat.amount(quote.max)},
              size: 10,
              weight: FontWeight.w900,
              letterSpacing: 0.5,
              color: p.accent,
              maxLines: 1,
            ),
          ],
        ),
        SizedBox(height: 12.ms),
        // RN: box with paddingLeft 32 / paddingRight 80, "₹" absolute at
        // (16, 14), MAX absolute at right 8, top 8.
        SizedBox(
          height: 56.ms,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  padding: EdgeInsets.only(left: 32.ms, right: 80.ms),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: p.inputBg,
                    borderRadius: BorderRadius.circular(18.ms),
                    border: Border.all(color: p.inputBorder),
                  ),
                  child: CText.raw(
                    quote.amountText.isEmpty ? '0.00' : quote.amountText,
                    size: 20,
                    weight: FontWeight.w900,
                    color: p.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Positioned(
                left: 16.ms,
                top: 14.ms,
                child: CText.raw(
                  '₹',
                  size: 18,
                  weight: FontWeight.w900,
                  color: p.subtle,
                ),
              ),
              Positioned(
                right: 8.ms,
                top: 8.ms,
                child: Pressable(
                  onPressed: onMax,
                  child: Container(
                    height: 40.ms,
                    padding: EdgeInsets.symmetric(horizontal: 14.ms),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0x10 / 255),
                      borderRadius: BorderRadius.circular(12.ms),
                      border: Border.all(color: p.accent, width: 1.5),
                    ),
                    child: CText(
                      'payment:transfer.max',
                      size: 11,
                      weight: FontWeight.w900,
                      letterSpacing: 1,
                      color: p.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.ms),
        Row(
          children: [
            for (final (i, percent) in TransferQuote.presets.indexed) ...[
              if (i > 0) SizedBox(width: 8.ms),
              Expanded(
                child: Pressable(
                  onPressed: () => onPreset(percent),
                  child: Container(
                    height: 38.ms,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selectedPreset == percent
                          ? p.accent.withValues(alpha: 0x15 / 255)
                          : p.cardBg,
                      borderRadius: BorderRadius.circular(12.ms),
                      border: Border.all(
                        color: selectedPreset == percent
                            ? p.accent
                            : p.cardBorder,
                      ),
                    ),
                    child: CText.raw(
                      '$percent%',
                      size: 12,
                      weight: FontWeight.w900,
                      letterSpacing: 1,
                      color: selectedPreset == percent ? p.accent : p.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Credit to Cash / GST / Total Deducted.
class TransferSummary extends StatelessWidget {
  const TransferSummary({super.key, required this.quote});

  final TransferQuote quote;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final has = quote.amount > 0;
    Widget row({
      required Widget label,
      required String value,
      required Color color,
      double size = 13,
    }) => Padding(
      padding: EdgeInsets.only(bottom: 8.ms),
      child: Row(
        children: [
          Expanded(child: label),
          CText.raw(
            has ? value : '—',
            size: size,
            weight: FontWeight.w900,
            color: color,
          ),
        ],
      ),
    );

    return Container(
      // RN: padding 20 and every row keeps its 8 bottom margin.
      padding: EdgeInsets.all(20.ms),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(24.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          row(
            label: CText(
              'payment:transfer.credit',
              size: 13,
              weight: FontWeight.w800,
              color: p.muted,
            ),
            value: '+ ₹${WalletFormat.amount(quote.amount)}',
            color: p.accent,
          ),
          row(
            label: CText(
              'payment:transfer.gst',
              variables: {'percent': WalletFormat.js(quote.gstPercent)},
              size: 13,
              weight: FontWeight.w800,
              color: p.muted,
            ),
            value: '₹${WalletFormat.amount(quote.gst)}',
            color: p.text,
          ),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12.ms),
            child: Container(height: 1, color: p.cardBorder),
          ),
          row(
            label: CText(
              'payment:transfer.total',
              size: 14,
              weight: FontWeight.w900,
              color: p.text,
            ),
            value: '- ₹${WalletFormat.amount(quote.debit)}',
            color: p.accent,
            size: 14,
          ),
        ],
      ),
    );
  }
}
