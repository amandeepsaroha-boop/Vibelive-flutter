import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../component/c_state_view.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/wallet_palette.dart';
import 'bank_form_view.dart';
import 'bank_status.dart';
import 'wallet_header.dart';

/// "Bank account" sheet (RN WithdrawalModal): the payout account's status
/// once one is saved, the form before that. A saved account is not editable
/// here — pending or verified, changing where payouts go is done by support.
Future<void> showBankSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // RN Modal: no drag to dismiss; the backdrop or X closes it.
  enableDrag: false,
  backgroundColor: AppColors.transparent,
  barrierColor: AppColors.blackA(0.7),
  builder: (_) => const _BankSheet(),
);

class _BankSheet extends HookWidget {
  const _BankSheet();

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final query = useBankDetail(context);
    final detail = query.data;

    final Widget body;
    if (detail != null) {
      body = BankStatusView(detail: detail);
    } else if (query.isError && query.error != null) {
      body = CStateView.error(
        context,
        query.error!,
        onRetry: () => query.refetch(),
      );
    } else if (query.isLoading) {
      body = const _BankSkeleton();
    } else {
      body = const BankFormView();
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.ms),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36.ms)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(
          bottom:
              10.ms +
              MediaQuery.paddingOf(context).bottom +
              MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40.ms,
                height: 4.ms,
                margin: EdgeInsets.symmetric(vertical: 8.ms),
                decoration: BoxDecoration(
                  color: p.dark
                      ? AppColors.whiteA(0.12)
                      : AppColors.blackA(0.12),
                  borderRadius: BorderRadius.circular(2.ms),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 14.ms),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CText(
                          'payment:bank.title',
                          size: 20,
                          weight: FontWeight.w900,
                          letterSpacing: -0.5,
                          color: p.text,
                          maxLines: 1,
                        ),
                        SizedBox(height: 2.ms),
                        CText(
                          'payment:bank.subtitle',
                          size: 10,
                          weight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: p.accent,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  WalletIconButton(
                    icon: LucideIcons.x,
                    size: 36,
                    radius: 12,
                    iconSize: 18,
                    semanticLabel: context.t('actions.close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            body,
          ],
        ),
      ),
    );
  }
}

class _BankSkeleton extends StatelessWidget {
  const _BankSkeleton();

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SkeletonBox(height: 64.ms, radius: 18),
        SizedBox(height: 12.ms),
        SkeletonBox(height: 150.ms, radius: 18),
      ],
    ),
  );
}

/// The wallet header's payout-account button: "Add bank account" until one
/// is saved, then its review state. Opens [showBankSheet].
class BankButton extends HookWidget {
  const BankButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final query = useBankDetail(context);
    final detail = query.data;
    final (label, tone) = switch (detail) {
      null when query.isLoading => ('payment:bank.button', p.text),
      null => ('payment:bank.add', p.accent),
      BankDetail(isVerified: true) => (
        'payment:bank.added_short',
        WalletPalette.success,
      ),
      _ => ('payment:bank.pending_short', WalletPalette.pending),
    };
    final fill = Color.alphaBlend(p.soft, p.bg);
    return Pressable(
      onPressed: () => unawaited(showBankSheet(context)),
      semanticLabel: context.t('payment:bank.title'),
      child: Container(
        height: 38.ms,
        padding: EdgeInsets.symmetric(horizontal: 12.ms),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14.ms),
          border: Border.all(color: Color.alphaBlend(p.cardBorder, fill)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.landmark, size: 15.ms, color: tone),
            SizedBox(width: 6.ms),
            CText(
              label,
              size: 10,
              weight: FontWeight.w900,
              letterSpacing: 1,
              color: tone,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}
