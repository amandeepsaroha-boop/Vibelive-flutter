import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../helper/wallet_amounts.dart';
import '../helper/wallet_format.dart';
import '../helper/wallet_palette.dart';
import 'transfer_parts.dart';
import 'wallet_header.dart';

/// "Earnings → Cash" sheet (RN TransferModal). True when a transfer went
/// through.
Future<bool> showTransferSheet(
  BuildContext context, {
  required double cash,
  required double earnings,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // RN Modal: no drag to dismiss; the backdrop or X closes it.
      enableDrag: false,
      backgroundColor: AppColors.transparent,
      barrierColor: AppColors.blackA(0.7),
      builder: (_) => _TransferSheet(cash: cash, earnings: earnings),
    ) ??
    false;

class _TransferSheet extends HookWidget {
  const _TransferSheet({required this.cash, required this.earnings});

  final double cash;
  final double earnings;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final gst = useGstConfig(context);
    final gstPercent = gst.data?.igstRate ?? GstConfig.defaultIgstRate;
    final amountText = useState('');
    final preset = useState<int?>(null);
    final transfer = useTransferEarningsToCash();
    // fquery's isPending lags a frame: a second tap must not resend.
    final busy = useRef(false);
    final quote = TransferQuote(
      amountText: amountText.value,
      earnings: earnings,
      gstPercent: gstPercent,
    );

    void pickPreset(int percent) {
      if (percent == 100) {
        preset.value = null;
        amountText.value = quote.maxText;
      } else {
        preset.value = percent;
        amountText.value = quote.presetText(percent);
      }
    }

    void pickMax() {
      preset.value = null;
      amountText.value = quote.maxText;
    }

    Future<void> confirm() async {
      if (busy.value || transfer.isPending) return;
      if (quote.belowMinimum) {
        unawaited(
          CAlert.show(
            title: 'payment:transfer.invalid_title',
            message: 'payment:transfer.min_message',
            variables: {'min': WalletFormat.js(EarningsTransfer.minAmount)},
            variant: CAlertVariant.warning,
          ),
        );
        return;
      }
      if (quote.exceedsEarnings) {
        unawaited(
          CAlert.show(
            title: 'payment:transfer.insufficient_title',
            message: 'payment:transfer.insufficient_message',
            variant: CAlertVariant.warning,
          ),
        );
        return;
      }
      busy.value = true;
      try {
        // Null means another transfer is still running: not a success.
        final result = await transfer.mutateAsync(quote.amount);
        if (result == null) return;
      } on ApiException catch (e) {
        unawaited(CAlert.error(e, title: 'payment:transfer.failed_title'));
        return;
      } finally {
        busy.value = false;
      }
      if (context.mounted) Navigator.of(context).pop(true);
      unawaited(
        CAlert.show(
          title: 'payment:transfer.success_title',
          message: 'payment:transfer.success',
          variant: CAlertVariant.success,
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(minHeight: 450.ms),
      padding: EdgeInsets.symmetric(horizontal: 20.ms),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36.ms)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        // RN ScrollView paddingBottom 40, no safe-area inset.
        padding: EdgeInsets.only(bottom: 40.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40.ms,
                height: 4.ms,
                margin: EdgeInsets.only(top: 14.ms, bottom: 22.ms),
                decoration: BoxDecoration(
                  color: AppColors.whiteA(0.12),
                  borderRadius: BorderRadius.circular(2.ms),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 16.ms),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 44.ms),
                    child: CText(
                      'payment:transfer.title',
                      size: 20,
                      weight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: p.text,
                      align: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: WalletIconButton(
                      icon: LucideIcons.x,
                      size: 36,
                      radius: 12,
                      iconSize: 18,
                      semanticLabel: context.t('actions.close'),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 24.ms),
              child: CText(
                'payment:transfer.subtitle',
                size: 12,
                weight: FontWeight.w700,
                height: 18,
                color: p.muted,
                align: TextAlign.center,
              ),
            ),
            TransferWallets(cash: cash, earnings: earnings),
            SizedBox(height: 28.ms),
            TransferAmountBox(
              quote: quote,
              selectedPreset: preset.value,
              onMax: pickMax,
              onPreset: pickPreset,
            ),
            SizedBox(height: 28.ms),
            TransferSummary(quote: quote),
            SizedBox(height: 32.ms),
            CButton(
              title: 'payment:transfer.confirm',
              loading: transfer.isPending,
              disabled: !quote.isValid || transfer.isPending,
              onPressed: confirm,
            ),
          ],
        ),
      ),
    );
  }
}
