import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
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
/// through. [source]: where it was opened (analytics: `wallet`,
/// `balance_gate`).
Future<bool> showTransferSheet(
  BuildContext context, {
  required double cash,
  required double earnings,
  String? source,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      routeSettings: ScreenTracker.sheet('transfer_sheet'),
      isScrollControlled: true,
      useSafeArea: true,
      // RN Modal: no drag to dismiss; the backdrop or X closes it.
      enableDrag: false,
      backgroundColor: AppColors.transparent,
      barrierColor: AppColors.blackA(0.7),
      builder: (_) =>
          _TransferSheet(cash: cash, earnings: earnings, source: source),
    ) ??
    false;

class _TransferSheet extends HookWidget {
  const _TransferSheet({
    required this.cash,
    required this.earnings,
    this.source,
  });

  final double cash;
  final double earnings;
  final String? source;

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
    final transferred = useRef(false);
    useEffect(() {
      PaymentEvents.transferOpened(
        source: source,
        earnings: earnings,
        cash: cash,
      );
      return () => PaymentEvents.transferClosed(done: transferred.value);
    }, const []);

    void pickPreset(int percent) {
      PaymentEvents.transferPreset(percent);
      if (percent == 100) {
        preset.value = null;
        amountText.value = quote.maxText;
      } else {
        preset.value = percent;
        amountText.value = quote.presetText(percent);
      }
    }

    void pickMax() {
      PaymentEvents.transferPreset(100);
      preset.value = null;
      amountText.value = quote.maxText;
    }

    Future<void> confirm() async {
      if (busy.value || transfer.isPending) return;
      if (quote.belowMinimum) {
        PaymentEvents.transferInvalid(
          reason: 'below_min',
          amount: quote.amount,
        );
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
        PaymentEvents.transferInvalid(
          reason: 'exceeds_earnings',
          amount: quote.amount,
        );
        unawaited(
          CAlert.show(
            title: 'payment:transfer.insufficient_title',
            message: 'payment:transfer.insufficient_message',
            variant: CAlertVariant.warning,
          ),
        );
        return;
      }
      // Cash is call credit, not money the host can take out: say so at the
      // moment of the transfer, and only go on when they confirm.
      busy.value = true;
      final accepted = await CAlert.confirm(
        title: 'payment:transfer.warn_title',
        message: 'payment:transfer.warn_message',
        variables: {'amount': WalletFormat.js(quote.amount)},
        confirmLabel: 'payment:transfer.warn_confirm',
      );
      PaymentEvents.transferWarning(accepted: accepted, amount: quote.amount);
      if (!accepted) {
        busy.value = false;
        return;
      }
      PaymentEvents.transferSubmitted(
        amount: quote.amount,
        gstPercent: gstPercent,
      );
      try {
        // Null means another transfer is still running: not a success.
        final result = await transfer.mutateAsync(quote.amount);
        if (result == null) return;
      } on ApiException catch (e) {
        PaymentEvents.transferFailed(
          amount: quote.amount,
          error: Analytics.errorCode(e),
        );
        unawaited(CAlert.error(e, title: 'payment:transfer.failed_title'));
        return;
      } finally {
        busy.value = false;
      }
      transferred.value = true;
      PaymentEvents.transferSuccess(amount: quote.amount);
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
      constraints: const BoxConstraints(),
      padding: EdgeInsets.symmetric(horizontal: 20.ms),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36.ms)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        // RN ScrollView paddingBottom 40, no safe-area inset.
        padding: EdgeInsets.only(
          bottom: 10.ms + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40.ms,
                height: 4.ms,
                margin: EdgeInsets.only(top: 8.ms, bottom: 8.ms),
                decoration: BoxDecoration(
                  // RN's white handle vanished on the light sheet.
                  color: p.dark
                      ? AppColors.whiteA(0.12)
                      : AppColors.blackA(0.12),
                  borderRadius: BorderRadius.circular(2.ms),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 4.ms),
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
              padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 10.ms),
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
            SizedBox(height: 12.ms),
            TransferAmountBox(
              quote: quote,
              selectedPreset: preset.value,
              onMax: pickMax,
              onPreset: pickPreset,
            ),
            SizedBox(height: 12.ms),
            TransferSummary(quote: quote),
            SizedBox(height: 12.ms),
            Container(
              padding: EdgeInsets.all(12.ms),
              decoration: BoxDecoration(
                color: WalletPalette.pending.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14.ms),
                border: Border.all(
                  color: WalletPalette.pending.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    size: 16.ms,
                    color: WalletPalette.pending,
                  ),
                  SizedBox(width: 8.ms),
                  Expanded(
                    child: CText(
                      'payment:transfer.no_withdraw',
                      size: 12,
                      weight: FontWeight.w700,
                      height: 17,
                      color: p.text,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14.ms),
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
