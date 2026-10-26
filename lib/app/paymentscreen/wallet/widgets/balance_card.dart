import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';

/// The wallet's balance card, laid out like a standard bank card: one left
/// edge, an 8-pt spacing grid, sentence-case labels. On the same surface as
/// the list below (soft accent tint, accent bubbles). Total balance on top;
/// cash | earnings as two columns under a hairline; then two equal actions,
/// Add money (filled) and Transfer (outlined). [balance] null: placeholders.
/// [showSplit] false (iOS, like RN) hides the split and Transfer.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.balance,
    required this.showSplit,
    required this.onAdd,
    required this.onTransfer,
  });

  final WalletBalance? balance;
  final bool showSplit;
  final VoidCallback onAdd;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final b = balance;
    final cash = b?.cashBalance ?? 0;
    final earnings = b?.earningsBalance ?? 0;
    // Same surface as the list below, lifted by a soft accent tint.
    Color tint(double a) =>
        Color.alphaBlend(p.accent.withValues(alpha: a), p.cardBg);

    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, 8.ms),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22.ms),
          border: Border.all(color: p.accent.withValues(alpha: 0.18)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tint(p.dark ? 0.14 : 0.12), tint(0.03)],
          ),
        ),
        child: Stack(
          children: [
            // Bubbles: plain shapes off the edges (no blur, no layer).
            Positioned(
              top: -46.ms,
              right: -30.ms,
              child: _Bubble(size: 130.ms, color: p.accent, alpha: 0.10),
            ),
            Positioned(
              top: 34.ms,
              right: 70.ms,
              child: _Bubble(size: 26.ms, color: p.accent, alpha: 0.08),
            ),
            Positioned(
              bottom: -40.ms,
              left: -24.ms,
              child: _Bubble(size: 96.ms, color: p.accent, alpha: 0.07),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.ms, 14.ms, 16.ms, 16.ms),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CText(
                          'payment:wallet.total_balance_label',
                          size: 12.5,
                          weight: FontWeight.w600,
                          color: p.muted,
                          maxLines: 1,
                        ),
                      ),
                      Icon(LucideIcons.wallet, size: 18.ms, color: p.accent),
                    ],
                  ),
                  SizedBox(height: 4.ms),
                  _Money(
                    b == null ? null : cash + earnings,
                    size: 28,
                    color: p.text,
                    placeholder: Size(150.ms, 32.ms),
                  ),
                  if (showSplit) ...[
                    SizedBox(height: 12.ms),
                    Container(height: 1, color: p.cardBorder),
                    SizedBox(height: 12.ms),
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _Stat(
                              label: 'payment:wallet.cash_label',
                              amount: b == null ? null : cash,
                            ),
                          ),
                          Container(width: 1, color: p.cardBorder),
                          SizedBox(width: 16.ms),
                          Expanded(
                            child: _Stat(
                              label: 'payment:wallet.earnings_label',
                              amount: b == null ? null : earnings,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 14.ms),
                  Row(
                    children: [
                      Expanded(
                        child: _Action(
                          label: 'payment:wallet.add_money',
                          icon: LucideIcons.plus,
                          filled: true,
                          onPressed: onAdd,
                        ),
                      ),
                      if (showSplit) ...[
                        SizedBox(width: 12.ms),
                        Expanded(
                          child: _Action(
                            label: 'payment:wallet.transfer_short',
                            icon: LucideIcons.arrowLeftRight,
                            filled: false,
                            semanticLabel: context.t('payment:wallet.transfer'),
                            onPressed: onTransfer,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.color, required this.alpha});
  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: alpha),
      ),
    ),
  );
}

/// `₹1,234.5`, shrinking rather than cut off; a soft bar while unknown.
class _Money extends StatelessWidget {
  const _Money(
    this.amount, {
    required this.size,
    required this.color,
    required this.placeholder,
  });

  final double? amount;
  final double size;
  final Color color;
  final Size placeholder;

  @override
  Widget build(BuildContext context) {
    final value = amount;
    if (value == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: placeholder.width,
          height: placeholder.height,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8.ms),
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: CText.raw(
        '₹${WalletFormat.amount(value)}',
        size: size,
        weight: FontWeight.w800,
        letterSpacing: -0.5,
        color: color,
        maxLines: 1,
      ),
    );
  }
}

/// "Cash" over its amount, left-aligned.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.amount});

  final String label;
  final double? amount;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CText(
          label,
          size: 11.5,
          weight: FontWeight.w600,
          color: p.muted,
          maxLines: 1,
        ),
        SizedBox(height: 2.ms),
        _Money(
          amount,
          size: 16,
          color: p.text,
          placeholder: Size(68.ms, 20.ms),
        ),
      ],
    );
  }
}

/// A 40 px action: filled (accent gradient) or outlined (accent).
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onPressed,
    this.semanticLabel,
  });

  /// i18n key.
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final fg = filled ? p.onAccent : p.accent;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: Container(
        height: 40.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: filled ? LinearGradient(colors: p.accentGradient) : null,
          color: filled ? null : p.cardBg,
          borderRadius: BorderRadius.circular(12.ms),
          border: filled
              ? null
              : Border.all(color: p.accent.withValues(alpha: 0.5), width: 1.2),
        ),
        // With a semantic label the visible text is not read on top of it.
        child: ExcludeSemantics(
          excluding: semanticLabel != null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16.ms, color: fg),
              SizedBox(width: 8.ms),
              Flexible(
                child: CText(
                  label,
                  size: 14,
                  weight: FontWeight.w700,
                  color: fg,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
