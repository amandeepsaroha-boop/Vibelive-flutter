import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/host_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/badge_payment_api.dart';
import '../../api/hosthub/eligibility.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/verification_models.dart';
import '../../api/paymentscreen/checkout_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../paymentscreen/wallet/helper/razorpay_gateway.dart';
import '../../paymentscreen/wallet/helper/topup_checkout.dart';
import '../../paymentscreen/wallet/widgets/payment_status.dart';
import '../common/host_page.dart';
import '../onboarding/helper/host_palette.dart';
import '../onboarding/widgets/continue_bar.dart';
import 'host_badge_screen.dart';

/// Verification fee (RN VerificationFeeScreen): creates the verification
/// record, skips ahead when there is nothing to pay or it is paid, else
/// takes the fee through Razorpay and waits for the backend to confirm.
class HostBadgeFeeScreen extends HookWidget {
  const HostBadgeFeeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final allowed = HostEligibility.canApplyForBadge(session.expert);
    // Created here when missing (RN `ensureVerificationRecord`).
    final record = useCurrentVerification(context, enabled: allowed);
    final pricing = usePricingConfig(context, enabled: allowed);
    final update = useUpdateVerification();
    final start = useStartBadgePayment();
    final confirm = useConfirmVerificationPayment();
    final busy = useState(false);
    // Analytics: the fee page was reported as viewed.
    final viewed = useRef(false);
    final p = HostPalette.of(context);

    final rec = record.data;
    final fee = pricing.data?.expertVerificationFees;
    // RN routing: nothing to pay → paid; paid → form; submitted → status.
    useEffect(() {
      if (rec == null || fee == null) return null;
      final step = rec.nextStep;
      Future<void> route() async {
        if (step == VerificationStep.fee && fee <= 0) {
          try {
            await update.mutateAsync(VerificationUpdate.markPaid(rec.key));
            HostEvents.badgeFeeWaived();
          } on ApiException catch (e) {
            HostEvents.badgeFeeError(error: Analytics.errorCode(e));
            await CAlert.error(e, title: 'hostflow:badge.fee_title');
            return;
          }
        }
        if (!context.mounted) return;
        if (step == VerificationStep.form ||
            (step == VerificationStep.fee && fee <= 0)) {
          context.pushReplacement(AppRoutes.verificationBadgeForm);
        } else if (step != VerificationStep.fee) {
          context.pushReplacement(AppRoutes.verificationBadge);
        }
      }

      route();
      return null;
    }, [rec?.key, rec?.nextStep, fee]);

    if (!allowed) {
      return const HostBadgeLocked(title: 'hostflow:badge.fee_title');
    }
    final error = record.error ?? pricing.error;
    if ((rec == null || fee == null) && error != null) {
      return HostPage(
        title: 'hostflow:badge.fee_title',
        body: CStateView.error(
          context,
          error,
          onRetry: () {
            record.refetch();
            pricing.refetch();
          },
        ),
      );
    }
    if (rec == null ||
        fee == null ||
        rec.nextStep != VerificationStep.fee ||
        fee <= 0) {
      return const HostPage(
        title: 'hostflow:badge.fee_title',
        body: HostPageSkeleton(),
      );
    }

    if (!viewed.value) {
      viewed.value = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => HostEvents.badgeFeeViewed(amount: fee),
      );
    }

    Future<void> pay() async {
      HostEvents.badgeFeePayTapped(amount: fee);
      busy.value = true;
      final payer = PayerInfo.fromUser(session.user);
      try {
        final begin = await start.mutateAsync((
          verificationId: rec.key,
          fee: fee,
          payer: payer,
        ));
        if (begin == null) return;
        final RazorpayCheckout checkout;
        switch (begin) {
          case BadgeAlreadyPaid():
            HostEvents.badgeFeeAlreadyPaid();
            if (context.mounted) {
              context.pushReplacement(AppRoutes.verificationBadgeForm);
            }
            return;
          case BadgeCheckout(checkout: final c):
            checkout = c;
        }
        HostEvents.badgeFeeCheckoutOpened(
          amount: fee,
          orderId: checkout.orderId,
        );
        final outcome = await RazorpayGateway.instance.open(
          checkout.toOptions(),
        );
        switch (outcome) {
          case CheckoutCancelled(:final end):
            HostEvents.badgeFeeCancelled(
              amount: fee,
              reason: end?.name ?? 'external_wallet',
            );
            return;
          case CheckoutFailed(:final description, :final code):
            HostEvents.badgeFeeFailed(
              amount: fee,
              error: code == null ? 'razorpay' : 'razorpay:$code',
            );
            if (context.mounted) {
              await showPaymentStatus(
                context,
                TopUpStatus(TopUpResult.failure, message: description),
                titleKey: 'hostflow:badge.pay_failed',
              );
            }
            return;
          case CheckoutPaid(:final paymentId, :final orderId, :final signature):
            final paid = await confirm.mutateAsync((
              verificationId: rec.key,
              payload: HostBadgePaymentApi.paymentResponse(
                paymentId: paymentId,
                orderId: orderId ?? checkout.orderId,
                signature: signature,
                fee: fee,
                payer: payer,
              ),
            ));
            if (paid == true) {
              HostEvents.badgeFeePaid(
                amount: fee,
                paymentId: paymentId ?? orderId ?? checkout.orderId,
                orderId: orderId ?? checkout.orderId,
              );
            } else {
              HostEvents.badgeFeePending(amount: fee);
            }
            if (!context.mounted) return;
            // The wallet's payment card: the success burst with the coin
            // sound, or the confirming ring while it is still pending.
            if (paid == true) {
              await showPaymentStatus(
                context,
                const TopUpStatus(TopUpResult.success),
                titleKey: 'hostflow:badge.pay_success',
                messageKey: 'hostflow:badge.pay_success_body',
              );
              if (context.mounted) {
                context.pushReplacement(AppRoutes.verificationBadgeForm);
              }
            } else {
              await showPaymentStatus(
                context,
                const TopUpStatus(TopUpResult.pending),
                titleKey: 'hostflow:badge.pay_pending',
                messageKey: 'hostflow:badge.pay_pending_body',
              );
            }
        }
      } on ApiException catch (e) {
        HostEvents.badgeFeeFailed(amount: fee, error: Analytics.errorCode(e));
        await CAlert.error(e, title: 'hostflow:badge.pay_failed');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return HostPage(
      title: 'hostflow:badge.fee_title',
      bottom: HostButton(
        key: const ValueKey('badge-pay'),
        label: 'hostflow:badge.pay_now',
        arrow: false,
        loading: busy.value,
        onPressed: pay,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 24.ms),
        children: [
          Container(
            padding: EdgeInsets.all(20.ms),
            decoration: BoxDecoration(
              color: p.tint,
              borderRadius: BorderRadius.circular(18.ms),
            ),
            child: Column(
              children: [
                Icon(LucideIcons.award, size: 40.ms, color: p.accent),
                SizedBox(height: 10.ms),
                CText(
                  'hostflow:badge.fee_body',
                  size: 14,
                  height: 20,
                  color: p.muted,
                  align: TextAlign.center,
                ),
                SizedBox(height: 14.ms),
                CText(
                  'hostflow:badge.fee_amount',
                  variables: {'amount': _money(fee)},
                  size: 28,
                  weight: FontWeight.w800,
                  color: p.text,
                ),
              ],
            ),
          ),
          SizedBox(height: 16.ms),
          Center(
            child: Pressable(
              onPressed: () =>
                  context.pushReplacement(AppRoutes.verificationBadge),
              hitPadding: EdgeInsets.all(8.ms),
              child: CText(
                'hostflow:badge.back_to_status',
                size: 14,
                weight: FontWeight.w700,
                color: p.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _money(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
