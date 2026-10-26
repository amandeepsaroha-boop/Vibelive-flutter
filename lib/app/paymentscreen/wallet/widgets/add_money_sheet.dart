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
import '../../../component/keyboard_inset.dart';
import '../../../component/pressable.dart';
import '../../../component/vibe_background.dart';
import '../helper/topup_checkout.dart';
import '../helper/wallet_amounts.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'wallet_header.dart';

/// How the add-money screen closed: an order to pay, or "profile
/// incomplete" (the wallet shows that alert). Null: closed by the user.
typedef AddMoneyExit = ({RazorpayCheckout? checkout, bool profileIncomplete});

/// Full-screen "Add Money" (RN modal, slide up): amount, presets, GST
/// breakdown, then the backend order. [initialAmount] pre-fills it (the call
/// balance gate, the first-top-up and exit-intent offers).
Future<AddMoneyExit?> showAddMoney(
  BuildContext context, {
  required TopUpCheckout flow,
  required PayerInfo Function() payer,
  double? initialAmount,
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
  pageBuilder: (_, _, _) =>
      _AddMoneyScreen(flow: flow, payer: payer, initialAmount: initialAmount),
);

class _AddMoneyScreen extends HookWidget {
  const _AddMoneyScreen({
    required this.flow,
    required this.payer,
    this.initialAmount,
  });

  final TopUpCheckout flow;
  final PayerInfo Function() payer;
  final double? initialAmount;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final config = useRuntimeConfig(context);
    final presets = config.presetAmounts;
    final initial = initialAmount;
    final initialText = initial != null && initial.isFinite && initial > 0
        ? WalletFormat.js(initial)
        : '';
    final controller = useTextEditingController(text: initialText);
    final preset = useValueNotifier<int?>(
      TopUpAmount.presetFor(initialText, presets),
    );
    final effective = useValueNotifier<double>(
      TopUpAmount.effective(initialText, null),
    );
    final loading = useValueNotifier<bool>(false);

    void sync() =>
        effective.value = TopUpAmount.effective(controller.text, preset.value);

    void onChanged(String text) {
      preset.value = TopUpAmount.presetFor(text, presets);
      sync();
    }

    void pick(int value) {
      if (preset.value == value) {
        preset.value = null;
        controller.clear();
      } else {
        preset.value = value;
        controller.text = '$value';
      }
      sync();
    }

    Future<void> submit() async {
      if (loading.value) return;
      final who = payer();
      if ((who.name ?? '').isEmpty || (who.email ?? '').isEmpty) {
        Navigator.of(context).pop((checkout: null, profileIncomplete: true));
        return;
      }
      final amount = TopUpAmount.effective(controller.text, preset.value);
      if (amount <= 0) {
        unawaited(
          CAlert.show(
            title: 'payment:add_money.invalid_title',
            message: 'payment:add_money.invalid_message',
            variant: CAlertVariant.warning,
          ),
        );
        return;
      }
      loading.value = true;
      try {
        final checkout = await flow.createOrder(
          amount: amount,
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
                  child: KeyboardInset(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          20.ms,
                          20.ms,
                          20.ms,
                          100.ms,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _SectionLabel(
                              'payment:add_money.enter_amount',
                            ),
                            _AmountField(
                              controller: controller,
                              onChanged: onChanged,
                            ),
                            SizedBox(height: 24.ms),
                            const _SectionLabel(
                              'payment:add_money.quick_select',
                            ),
                            ValueListenableBuilder<int?>(
                              valueListenable: preset,
                              builder: (_, selected, _) => _Presets(
                                options: presets,
                                selected: selected,
                                onPick: pick,
                              ),
                            ),
                            SizedBox(height: 28.ms),
                            ValueListenableBuilder<double>(
                              valueListenable: effective,
                              builder: (_, amount, _) => amount > 0
                                  ? _GstCard(
                                      amount: amount,
                                      percent: config.gstPercent,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            ListenableBuilder(
                              listenable: Listenable.merge([
                                effective,
                                loading,
                              ]),
                              builder: (_, _) => CButton(
                                title: 'payment:add_money.submit',
                                showArrow: false,
                                loading: loading.value,
                                disabled: effective.value <= 0,
                                onPressed: submit,
                              ),
                            ),
                          ],
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12.ms),
    child: CText(
      text,
      size: 10,
      weight: FontWeight.w900,
      letterSpacing: 2,
      color: WalletPalette.of(context).muted,
    ),
  );
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(22.ms),
      borderSide: BorderSide(color: color),
    );
    return MediaQuery.withNoTextScaling(
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [TopUpAmountFormatter()],
        textAlign: TextAlign.center,
        cursorColor: p.accent,
        style: TextStyle(
          fontSize: 32.ms,
          fontWeight: FontWeight.w900,
          color: p.text,
        ),
        decoration: InputDecoration(
          hintText: '₹0.00',
          hintStyle: TextStyle(
            fontSize: 32.ms,
            fontWeight: FontWeight.w900,
            color: p.subtle,
          ),
          filled: true,
          fillColor: p.inputBg,
          isDense: true,
          contentPadding: EdgeInsets.all(16.ms),
          enabledBorder: border(p.inputBorder),
          focusedBorder: border(p.inputBorder),
          border: border(p.inputBorder),
        ),
      ),
    );
  }
}

class _Presets extends StatelessWidget {
  const _Presets({
    required this.options,
    required this.selected,
    required this.onPick,
  });

  final List<int> options;
  final int? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Wrap(
      spacing: 10.ms,
      runSpacing: 10.ms,
      children: [
        for (final value in options)
          Pressable(
            onPressed: () => onPick(value),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 18.ms, vertical: 12.ms),
              decoration: BoxDecoration(
                color: value == selected
                    ? WalletPalette.presetSelectedBg
                    : p.inputBg,
                borderRadius: BorderRadius.circular(14.ms),
                border: Border.all(
                  color: value == selected ? p.accent : p.inputBorder,
                ),
              ),
              child: CText.raw(
                '₹${WalletFormat.whole(value)}',
                size: 14,
                weight: FontWeight.w900,
                color: value == selected ? p.accent : p.text,
              ),
            ),
          ),
      ],
    );
  }
}

/// Recharge amount, GST, total payable (RN GST breakdown).
class _GstCard extends StatelessWidget {
  const _GstCard({required this.amount, required this.percent});
  final double amount;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final b = TopUpAmount.breakdown(amount, percent);
    if (b.base <= 0) return const SizedBox.shrink();
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
            'payment:add_money.will_be_added',
            variables: {'amount': WalletFormat.fixed2(b.base)},
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
