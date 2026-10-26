import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/runtime_config_queries.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../../../component/vibe_background.dart';
import '../helper/topup_bonus.dart';
import '../helper/topup_checkout.dart';
import '../helper/wallet_amounts.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'amount_cards.dart';
import 'wallet_header.dart';

/// How the add-money screen closed: an order to pay, or "profile
/// incomplete" (the wallet shows that alert). Null: closed by the user.
typedef AddMoneyExit = ({RechargeCheckout? checkout, bool profileIncomplete});

/// Full-screen "Add Money" (RN modal, slide up): amount, presets, GST
/// breakdown, then the backend order. [initialAmount] pre-fills it (the call
/// balance gate, the first-top-up and exit-intent offers).
Future<AddMoneyExit?> showAddMoney(
  BuildContext context, {
  required TopUpCheckout flow,
  required PayerInfo Function() payer,
  double? initialAmount,
  TopUpBonus? bonus,
}) => showGeneralDialog<AddMoneyExit>(
  context: context,
  barrierDismissible: false,
  barrierColor: AppColors.transparent,
  transitionDuration: const Duration(milliseconds: 280),
  transitionBuilder: (_, anim, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
    child: child,
  ),
  pageBuilder: (_, _, _) => _AddMoneyScreen(
    flow: flow,
    payer: payer,
    initialAmount: initialAmount,
    bonus: bonus,
  ),
);

class _AddMoneyScreen extends HookWidget {
  const _AddMoneyScreen({
    required this.flow,
    required this.payer,
    this.initialAmount,
    this.bonus,
  });

  final TopUpCheckout flow;
  final PayerInfo Function() payer;
  final double? initialAmount;

  /// Previewed on the cards and in the breakdown (first top-up, come-back).
  final TopUpBonus? bonus;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final config = useRuntimeConfig(context);
    // An exact amount handed in (call balance gate, come-back offer) is
    // pre-selected; one that isn't a preset gets its own card.
    final initial = initialAmount;
    final prefill = initial != null && initial.isFinite && initial > 0
        ? initial.ceil()
        : null;
    final presets = config.presetAmounts;
    final options = [
      ...presets,
      if (prefill != null && !presets.contains(prefill)) prefill,
    ];
    final selected = useValueNotifier<int?>(prefill);
    final loading = useValueNotifier<bool>(false);

    void pick(int value) =>
        selected.value = selected.value == value ? null : value;

    Future<void> submit() async {
      final amount = selected.value;
      if (loading.value || amount == null) return;
      final who = payer();
      if ((who.name ?? '').isEmpty || (who.email ?? '').isEmpty) {
        Navigator.of(context).pop((checkout: null, profileIncomplete: true));
        return;
      }
      loading.value = true;
      try {
        final checkout = await flow.createOrder(
          amount: amount.toDouble(),
          payer: who,
          description: context.t('payment:add_money.description'),
          gstPercent: config.gstPercent,
        );
        if (context.mounted) {
          Navigator.of(
            context,
          ).pop((checkout: checkout, profileIncomplete: false));
        }
      } on ApiException catch (e) {
        unawaited(CAlert.error(e));
      } finally {
        if (context.mounted) loading.value = false;
      }
    }

    return Material(
      color: p.bg,
      child: Stack(
        children: [
          const VibeBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.ms,
                    vertical: 12.ms,
                  ),
                  child: Row(
                    children: [
                      WalletIconButton(
                        icon: LucideIcons.x,
                        semanticLabel: context.t('actions.close'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      SizedBox(width: 14.ms),
                      Expanded(
                        child: CText(
                          'payment:add_money.title',
                          size: 22,
                          weight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: p.text,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    // Top room for the "Most Popular" badge.
                    padding: EdgeInsets.fromLTRB(20.ms, 22.ms, 20.ms, 24.ms),
                    child: ValueListenableBuilder<int?>(
                      valueListenable: selected,
                      builder: (_, amount, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AmountCards(
                            options: options,
                            selected: amount,
                            onPick: pick,
                            gstPercent: config.gstPercent,
                            bonus: bonus,
                          ),
                          if (amount != null) ...[
                            SizedBox(height: 24.ms),
                            _GstCard(
                              amount: amount.toDouble(),
                              percent: config.gstPercent,
                              bonus: bonus,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Pinned: shown once a card is picked, never scrolls away.
                ValueListenableBuilder<int?>(
                  valueListenable: selected,
                  builder: (_, amount, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => SizeTransition(
                      sizeFactor: a,
                      axisAlignment: -1,
                      child: FadeTransition(opacity: a, child: child),
                    ),
                    child: amount == null
                        ? const SizedBox(width: double.infinity)
                        : Container(
                            key: const ValueKey('add-money-bar'),
                            padding: EdgeInsets.fromLTRB(
                              20.ms,
                              12.ms,
                              20.ms,
                              12.ms,
                            ),
                            decoration: BoxDecoration(
                              color: p.bg,
                              border: Border(
                                top: BorderSide(color: p.cardBorder),
                              ),
                            ),
                            child: ValueListenableBuilder<bool>(
                              valueListenable: loading,
                              builder: (_, busy, _) => CButton(
                                title: 'payment:add_money.submit',
                                showArrow: false,
                                loading: busy,
                                onPressed: submit,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recharge amount, GST, total payable (RN GST breakdown).
class _GstCard extends StatelessWidget {
  const _GstCard({required this.amount, required this.percent, this.bonus});
  final double amount;
  final double percent;
  final TopUpBonus? bonus;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final b = TopUpAmount.breakdown(amount, percent);
    if (b.base <= 0) return const SizedBox.shrink();
    final extra = bonus?.on(b.base) ?? 0;
    Widget row(Widget label, String value, {required Color color}) => Row(
      children: [
        Expanded(child: label),
        CText.raw(value, size: 13, weight: FontWeight.w900, color: color),
      ],
    );
    return Container(
      margin: EdgeInsets.only(bottom: 24.ms),
      padding: EdgeInsets.all(20.ms),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(24.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          row(
            CText(
              'payment:add_money.recharge_amount',
              size: 13,
              weight: FontWeight.w700,
              color: p.muted,
            ),
            '₹${WalletFormat.fixed2(b.base)}',
            color: p.text,
          ),
          SizedBox(height: 10.ms),
          row(
            CText(
              'payment:add_money.gst',
              variables: {'percent': WalletFormat.js(percent)},
              size: 13,
              weight: FontWeight.w700,
              color: p.muted,
            ),
            '₹${WalletFormat.fixed2(b.gst)}',
            color: p.text,
          ),
          SizedBox(height: 14.ms),
          Container(height: 1, color: p.cardBorder),
          SizedBox(height: 14.ms),
          Row(
            children: [
              Expanded(
                child: CText(
                  'payment:add_money.total_payable',
                  size: 15,
                  weight: FontWeight.w900,
                  color: p.text,
                ),
              ),
              CText.raw(
                '₹${WalletFormat.fixed2(b.total)}',
                size: 15,
                weight: FontWeight.w900,
                color: p.accent,
              ),
            ],
          ),
          SizedBox(height: 12.ms),
          CText(
            extra > 0
                ? 'payment:add_money.will_be_added_bonus'
                : 'payment:add_money.will_be_added',
            variables: {
              'amount': WalletFormat.fixed2(b.base + extra),
              'bonus': WalletFormat.whole(extra),
            },
            size: 11,
            weight: FontWeight.w700,
            italic: true,
            color: p.subtle,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
