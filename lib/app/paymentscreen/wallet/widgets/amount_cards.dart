import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/topup_bonus.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';

/// "Choose Amount": the preset top-ups as compact, near-square cards, three
/// per row, largest first. Without a bonus a card is just the amount. With
/// one (first top-up, come-back) it says what the wallet GETS (bonus
/// included), the bonus, and the amount you pay (GST is separate, at
/// checkout); a short
/// tier name, or with a [bonus] "₹100 + ₹20 bonus". The second-smallest is
/// "Most Popular". Tapping a card selects it (again: clears it).
class AmountCards extends StatelessWidget {
  const AmountCards({
    super.key,
    required this.options,
    required this.selected,
    required this.onPick,
    required this.gstPercent,
    this.bonus,
  });

  final List<int> options;
  final int? selected;
  final ValueChanged<int> onPick;
  final double gstPercent;
  final TopUpBonus? bonus;

  static const _columns = 3;

  /// Tier name (i18n key) of the [i]-th smallest of [n] amounts: first,
  /// second (popular) and last are fixed; the ones between take the middle
  /// names in order.
  static String _tierOf(int i, int n) {
    if (i == 0) return 'payment:tiers.starter';
    if (i == 1 && n > 2) return _popular;
    if (i == n - 1) return 'payment:tiers.max';
    return _middle[(i - 2).clamp(0, _middle.length - 1)];
  }

  static const _popular = 'payment:tiers.popular';
  static const _middle = [
    'payment:tiers.great',
    'payment:tiers.more',
    'payment:tiers.best',
    'payment:tiers.super',
    'payment:tiers.pro',
    'payment:tiers.premium',
  ];

  @override
  Widget build(BuildContext context) {
    // High to low; tiers still count from the smallest.
    final sorted = [...options]..sort((a, b) => b.compareTo(a));
    final n = sorted.length;
    final gap = 10.ms;
    return Column(
      children: [
        for (var r = 0; r * _columns < n; r++) ...[
          if (r > 0) SizedBox(height: gap),
          // Cards of a row share the tallest one's height: text never has
          // to shrink to fit a fixed box.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < _columns; c++) ...[
                  if (c > 0) SizedBox(width: gap),
                  Expanded(
                    child: r * _columns + c < n
                        ? _AmountCard(
                            value: sorted[r * _columns + c],
                            tier: _tierOf(n - 1 - (r * _columns + c), n),
                            selected: sorted[r * _columns + c] == selected,
                            anySelected: selected != null,
                            gstPercent: gstPercent,
                            bonus: bonus,
                            onTap: () => onPick(sorted[r * _columns + c]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.value,
    required this.tier,
    required this.selected,
    required this.anySelected,
    required this.gstPercent,
    required this.bonus,
    required this.onTap,
  });

  final int value;
  final double gstPercent;

  /// i18n key of the tier name.
  final String tier;
  final bool selected;
  final bool anySelected;
  final TopUpBonus? bonus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final popular = tier == AmountCards._popular;
    // The popular pill is filled until something else is picked.
    final filled = selected || (popular && !anySelected);
    final highlighted = selected || popular;
    final amount = '₹${WalletFormat.whole(value)}';
    final extra = bonus?.on(value) ?? 0;
    // The real amount: GST is separate, added at checkout.
    final pay = value.toDouble();
    final get = WalletFormat.whole(value + extra);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(8.ms, popular ? 14.ms : 10.ms, 8.ms, 9.ms),
      decoration: BoxDecoration(
        color: highlighted ? p.accent.withValues(alpha: 0.06) : p.cardBg,
        borderRadius: BorderRadius.circular(18.ms),
        border: Border.all(
          color: selected
              ? p.accent
              : popular
              ? p.accent.withValues(alpha: 0.45)
              : p.cardBorder,
          width: selected ? 1.8 : 1,
        ),
      ),
      // No bonus (not a first top-up): only the amount. With one: what the
      // wallet gets, the bonus, and what is paid.
      child: bonus == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WalletDot(color: p.accent),
                SizedBox(height: 8.ms),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CText.raw(
                    amount,
                    size: 20,
                    weight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: selected ? p.accent : p.text,
                    maxLines: 1,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                _WalletDot(color: p.accent),
                SizedBox(height: 6.ms),
                // Only the one-line figures may shrink, and only if they must.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CText(
                    'payment:tiers.you_get',
                    size: 9.5,
                    weight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: p.muted,
                    maxLines: 1,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: CText.raw(
                    '₹$get',
                    size: 19,
                    weight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: p.text,
                    maxLines: 1,
                  ),
                ),
                SizedBox(height: 2.ms),
                // Wraps instead of shrinking or cutting off.
                CText(
                  'payment:tiers.with_bonus',
                  variables: {'bonus': WalletFormat.whole(extra)},
                  size: 10.5,
                  weight: FontWeight.w800,
                  align: TextAlign.center,
                  color: _BonusColor.of(context),
                  maxLines: 2,
                ),
                const Spacer(),
                SizedBox(height: 8.ms),
                _Pill(pay: _money(pay), filled: filled),
              ],
            ),
    );

    return Pressable(
      onPressed: onTap,
      activeOpacity: 0.85,
      semanticLabel: amount,
      child: Stack(
        // The card takes the cell's full size (the row is equal-height).
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          card,
          if (popular) Positioned(top: -9.ms, child: const _PopularBadge()),
        ],
      ),
    );
  }
}

/// The wallet icon in a soft accent circle.
class _WalletDot extends StatelessWidget {
  const _WalletDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 28.ms,
    height: 28.ms,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.1),
    ),
    child: Icon(LucideIcons.wallet, size: 14.ms, color: color),
  );
}

/// `118` / `59.50`: whole rupees when it is whole.
String _money(double v) =>
    v == v.roundToDouble() ? WalletFormat.whole(v) : v.toStringAsFixed(2);

/// "Pay ₹100" (the amount; GST is added at checkout).
class _Pill extends StatelessWidget {
  const _Pill({required this.pay, required this.filled});
  final String pay;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 28.ms,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 6.ms),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: filled ? null : p.accent.withValues(alpha: 0.1),
        gradient: filled ? LinearGradient(colors: p.accentGradient) : null,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: CText(
          'payment:tiers.pay',
          variables: {'amount': pay},
          size: 11.5,
          weight: FontWeight.w800,
          color: filled ? p.onAccent : p.accent,
          maxLines: 1,
        ),
      ),
    );
  }
}

class _PopularBadge extends StatelessWidget {
  const _PopularBadge();

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.ms, vertical: 3.ms),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(colors: p.accentGradient),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.flame, size: 9.ms, color: p.onAccent),
          SizedBox(width: 2.ms),
          CText(
            'payment:tiers.most_popular',
            size: 8.5,
            weight: FontWeight.w800,
            color: p.onAccent,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// Success green for bonus text (lime on dark, where it reads).
abstract final class _BonusColor {
  static Color of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? BrandColors.lime
      : WalletPalette.success;
}
