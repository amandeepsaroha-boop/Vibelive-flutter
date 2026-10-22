import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';

/// Total balance + ADD, then cash ⇠ earnings with the transfer button (RN
/// balance card). [balance] null: skeletons. [showSplit] false hides the
/// cash / earnings row (RN hides it on iOS).
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, 6.ms),
      child: Container(
        padding: EdgeInsets.all(20.ms),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(28.ms),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Label(
                        'payment:wallet.total_balance',
                        size: 10,
                        ls: 2,
                      ),
                      SizedBox(height: 4.ms),
                      _Money(
                        b == null ? null : cash + earnings,
                        size: 26,
                        skeleton: Size(140.ms, 32.ms),
                        skeletonRadius: 8,
                        align: Alignment.centerLeft,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12.ms),
                _AddButton(onPressed: onAdd),
              ],
            ),
            SizedBox(height: 20.ms),
            Container(height: 1, color: p.cardBorder),
            SizedBox(height: 18.ms),
            if (showSplit)
              Padding(
                padding: EdgeInsets.only(top: 4.ms),
                child: Row(
                  children: [
                    Expanded(
                      child: _Split(
                        label: 'payment:wallet.cash',
                        hint: 'payment:wallet.cash_hint',
                        amount: b == null ? null : cash,
                        icon: LucideIcons.creditCard,
                        iconColor: AppColors.green,
                      ),
                    ),
                    _TransferButton(onPressed: onTransfer),
                    Expanded(
                      child: _Split(
                        label: 'payment:wallet.earnings',
                        hint: 'payment:wallet.earnings_hint',
                        amount: b == null ? null : earnings,
                        icon: LucideIcons.trendingUp,
                        iconColor: p.accent,
                      ),
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

class _Label extends StatelessWidget {
  const _Label(this.text, {required this.size, required this.ls});
  final String text;
  final double size;
  final double ls;

  @override
  Widget build(BuildContext context) => CText(
    text,
    size: size,
    weight: FontWeight.w900,
    letterSpacing: ls,
    color: WalletPalette.of(context).muted,
    maxLines: 1,
  );
}

/// `₹1,234.5`, shrinking rather than cut off; a skeleton while unknown.
class _Money extends StatelessWidget {
  const _Money(
    this.amount, {
    required this.size,
    required this.skeleton,
    required this.skeletonRadius,
    required this.align,
  });

  final double? amount;
  final double size;
  final Size skeleton;
  final double skeletonRadius;
  final Alignment align;

  @override
  Widget build(BuildContext context) {
    final value = amount;
    if (value == null) {
      return Shimmer(
        child: SkeletonBox(
          width: skeleton.width,
          height: skeleton.height,
          radius: skeletonRadius,
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align,
      child: CText.raw(
        '₹${WalletFormat.amount(value)}',
        size: size,
        weight: FontWeight.w900,
        color: WalletPalette.of(context).text,
        maxLines: 1,
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Pressable(
      onPressed: onPressed,
      child: Container(
        height: 40.ms,
        padding: EdgeInsets.only(left: 14.ms, right: 18.ms),
        decoration: BoxDecoration(
          color: p.accent,
          borderRadius: BorderRadius.circular(20.ms),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plus, size: 16.ms, color: p.onAccent, weight: 800),
            SizedBox(width: 4.ms),
            CText(
              'payment:wallet.add',
              size: 11,
              weight: FontWeight.w900,
              letterSpacing: 1.2,
              color: p.onAccent,
            ),
          ],
        ),
      ),
    );
  }
}

class _Split extends StatelessWidget {
  const _Split({
    required this.label,
    required this.hint,
    required this.amount,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String hint;
  final double? amount;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Column(
      children: [
        _Label(label, size: 9, ls: 1.5),
        SizedBox(height: 4.ms),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: _Money(
                amount,
                size: 18,
                skeleton: Size(80.ms, 24.ms),
                skeletonRadius: 6,
                align: Alignment.center,
              ),
            ),
            SizedBox(width: 6.ms),
            Icon(icon, size: 18.ms, color: iconColor),
          ],
        ),
        SizedBox(height: 4.ms),
        CText(
          hint,
          size: 9,
          weight: FontWeight.w700,
          color: p.subtle,
          maxLines: 1,
          align: TextAlign.center,
        ),
      ],
    );
  }
}

/// Crisp ringed circle between the two wallets (no glow): opens the
/// transfer sheet.
class _TransferButton extends StatelessWidget {
  const _TransferButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.ms),
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: context.t('payment:wallet.transfer'),
        // One shape for fill, ring and glow (stroke kept inside the edge):
        // a separate border + shadow left a broken-looking ring on device.
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: 44.ms,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: p.dark ? AppColors.darkSurface : AppColors.white,
                shape: CircleBorder(
                  side: BorderSide(
                    color: p.accent,
                    width: 2.5,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
              ),
              child: Center(
                child: Icon(
                  LucideIcons.arrowLeft,
                  size: 22.ms,
                  color: p.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
