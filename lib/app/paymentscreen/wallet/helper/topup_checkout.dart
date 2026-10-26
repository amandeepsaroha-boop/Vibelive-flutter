import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/network/api_exception.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import 'checkout_outcome.dart';
import 'razorpay_gateway.dart';

/// A checkout the person closed unpaid (`/razorpay/payments/:id/abandon`).
@immutable
class AbandonReport {
  const AbandonReport({
    required this.orderRef,
    required this.end,
    this.code,
    this.description,
  });

  /// Transaction id, else the order id.
  final String orderRef;
  final CheckoutEnd end;
  final int? code;
  final String? description;
}

/// How a top-up ended, for the status dialog.
enum TopUpResult { success, pending, failure }

@immutable
class TopUpStatus {
  const TopUpStatus(this.result, {this.messageKey, this.message});

  final TopUpResult result;

  /// i18n key of the reason (verification failed, pending…).
  final String? messageKey;

  /// Gateway text of a failure, shown as is (RN).
  final String? message;
}

/// RN WalletScreen's Razorpay top-up: the backend creates the order, the
/// native checkout takes the payment, the backend verifies it (with status
/// recovery), then the outcome is reported in the background. No key secret
/// is ever used: the order comes from the backend.
class TopUpCheckout {
  TopUpCheckout({
    RazorpayGateway? gateway,
    Future<RechargeCheckout> Function(RechargeRequest request)? start,
    Future<RazorpayVerification> Function(RazorpayPayment payment)? verify,
    Future<void> Function(RechargeReport report)? reportSuccess,
    Future<void> Function(RechargeReport report)? reportFailure,
    Future<void> Function(AbandonReport report)? reportAbandoned,
  }) : _gateway = gateway,
       _start = start ?? startWalletRecharge,
       _verify = verify ?? verifyRazorpayPayment,
       _reportSuccess = reportSuccess ?? reportRechargeSuccess,
       _reportFailure = reportFailure ?? reportRechargeFailure,
       _reportAbandoned = reportAbandoned ?? _sendAbandoned;

  final RazorpayGateway? _gateway;
  final Future<RechargeCheckout> Function(RechargeRequest) _start;
  final Future<RazorpayVerification> Function(RazorpayPayment) _verify;
  final Future<void> Function(RechargeReport) _reportSuccess;
  final Future<void> Function(RechargeReport) _reportFailure;
  final Future<void> Function(AbandonReport) _reportAbandoned;

  static Future<void> _sendAbandoned(AbandonReport r) =>
      reportCheckoutAbandoned(
        transactionId: r.orderRef,
        classification: r.end.wire,
        errorCode: r.code,
        description: r.description,
      );

  /// True while the backend verifies a payment ("Verifying Payment...").
  final ValueNotifier<bool> verifying = ValueNotifier(false);

  /// Creates the order on the gateway the backend selected. Throws
  /// [ApiException] (shown by the add-money sheet).
  Future<RazorpayCheckout> createOrder({
    required double amount,
    required PayerInfo payer,
    required String description,
    double gstPercent = GstConfig.defaultIgstRate,
  }) async {
    final checkout = await _start(
      RechargeRequest(
        amount: amount,
        payer: payer,
        description: description,
        gstPercent: gstPercent,
      ),
    );
    if (checkout is RazorpayCheckout) return checkout;
    // PayU needs a WebView form post, which the app doesn't ship.
    throw const ApiException(
      ApiErrorType.rejected,
      messageKey: 'payment:errors.gateway_unavailable',
    );
  }

  /// Opens the checkout for [checkout] and settles it. Null when the user
  /// closed the checkout (RN: nothing shown); [onAbandoned] then runs when
  /// that was the person's own choice (the exit-intent offer).
  Future<TopUpStatus?> pay(
    RazorpayCheckout checkout,
    PayerInfo payer, {
    VoidCallback? onAbandoned,
  }) async {
    final gateway = _gateway ?? RazorpayGateway.instance;
    final outcome = await gateway.open(checkout.toOptions());
    switch (outcome) {
      case CheckoutCancelled(:final end, :final code, :final description):
        if (end != null) _logEnd(checkout, end, code, description);
        if (end == CheckoutEnd.userDismissed) onAbandoned?.call();
        return null;
      case CheckoutFailed(:final end, :final code, :final description):
        if (end == CheckoutEnd.failedToOpen) {
          _logEnd(checkout, end, code, description);
        }
        return _fail(checkout, payer, message: description);
      case final CheckoutPaid paid:
        return _settle(checkout, payer, paid);
    }
  }

  /// RN recorded nothing when checkout closed unpaid, so a lost sale could
  /// not be told from a checkout that never opened. A failure to open is
  /// not reported as abandoned: the sweeper marks it if nothing lands.
  void _logEnd(
    RazorpayCheckout checkout,
    CheckoutEnd end,
    int? code,
    String? description,
  ) {
    final orderRef = checkout.txnId.isNotEmpty
        ? checkout.txnId
        : checkout.orderId;
    final dismissed = end == CheckoutEnd.userDismissed;
    Analytics.log(dismissed ? 'payment_abandoned' : 'checkout_failed_to_open', {
      'order_id': orderRef,
      'amount': checkout.baseAmount,
      'error_code': code,
      'description': description,
    });
    if (!dismissed) return;
    unawaited(
      _reportAbandoned(
        AbandonReport(
          orderRef: orderRef,
          end: end,
          code: code,
          description: description,
        ),
      ).catchError((Object _) {}),
    );
  }

  Future<TopUpStatus> _settle(
    RazorpayCheckout checkout,
    PayerInfo payer,
    CheckoutPaid paid,
  ) async {
    final paymentId = paid.paymentId ?? '';
    final orderId = paid.orderId ?? checkout.orderId;
    final signature = paid.signature;
    verifying.value = true;
    try {
      if (paymentId.isNotEmpty) {
        final result = await _verify(
          RazorpayPayment(
            paymentId: paymentId,
            orderId: orderId,
            signature: signature,
            transactionId: checkout.txnId,
          ),
        );
        switch (result.outcome) {
          case VerificationOutcome.pending:
            return const TopUpStatus(
              TopUpResult.pending,
              messageKey: 'payment:verification.pending',
            );
          case VerificationOutcome.failed:
            return _fail(
              checkout,
              payer,
              messageKey: 'payment:errors.verification_failed',
            );
          case VerificationOutcome.success:
            break;
        }
      }
      unawaited(
        _reportSuccess(
          RechargeReport(
            gateway: PaymentGateway.razorpay,
            payer: payer,
            txnId: checkout.txnId,
            amount: checkout.baseAmount,
            razorpayPaymentId: paymentId,
            razorpayOrderId: orderId,
            razorpaySignature: signature,
          ),
        ),
      );
      return const TopUpStatus(TopUpResult.success);
    } on ApiException catch (e) {
      // With a payment id the money is most likely taken: never a false
      // failure (RN).
      return paymentId.isNotEmpty
          ? const TopUpStatus(
              TopUpResult.pending,
              messageKey: 'payment:verification.pending',
            )
          : _fail(checkout, payer, messageKey: e.i18nKey);
    } finally {
      verifying.value = false;
    }
  }

  TopUpStatus _fail(
    RazorpayCheckout checkout,
    PayerInfo payer, {
    String? message,
    String? messageKey,
  }) {
    unawaited(
      _reportFailure(
        RechargeReport(
          gateway: PaymentGateway.razorpay,
          payer: payer,
          txnId: checkout.txnId,
          amount: checkout.baseAmount,
          failureReason: message ?? 'Payment failed',
        ),
      ),
    );
    return TopUpStatus(
      TopUpResult.failure,
      message: message,
      messageKey: messageKey,
    );
  }

  void dispose() => verifying.dispose();
}
