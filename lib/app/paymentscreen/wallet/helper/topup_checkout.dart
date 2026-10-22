import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exception.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import 'razorpay_gateway.dart';

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
  }) : _gateway = gateway,
       _start = start ?? startWalletRecharge,
       _verify = verify ?? verifyRazorpayPayment,
       _reportSuccess = reportSuccess ?? reportRechargeSuccess,
       _reportFailure = reportFailure ?? reportRechargeFailure;

  final RazorpayGateway? _gateway;
  final Future<RechargeCheckout> Function(RechargeRequest) _start;
  final Future<RazorpayVerification> Function(RazorpayPayment) _verify;
  final Future<void> Function(RechargeReport) _reportSuccess;
  final Future<void> Function(RechargeReport) _reportFailure;

  /// True while the backend verifies a payment ("Verifying Payment...").
  final ValueNotifier<bool> verifying = ValueNotifier(false);

  /// Creates the order on the gateway the backend selected. Throws
  /// [ApiException] (shown by the add-money sheet).
  Future<RazorpayCheckout> createOrder({
    required double amount,
    required PayerInfo payer,
    required String description,
  }) async {
    final checkout = await _start(
      RechargeRequest(amount: amount, payer: payer, description: description),
    );
    if (checkout is RazorpayCheckout) return checkout;
    // PayU needs a WebView form post, which the app doesn't ship.
    throw const ApiException(
      ApiErrorType.rejected,
      messageKey: 'payment:errors.gateway_unavailable',
    );
  }

  /// Opens the checkout for [checkout] and settles it. Null when the user
  /// closed the checkout (RN: nothing shown).
  Future<TopUpStatus?> pay(RazorpayCheckout checkout, PayerInfo payer) async {
    final gateway = _gateway ?? RazorpayGateway.instance;
    final outcome = await gateway.open(checkout.toOptions());
    return switch (outcome) {
      CheckoutCancelled() => null,
      CheckoutFailed(:final description) => _fail(
        checkout,
        payer,
        message: description,
      ),
      final CheckoutPaid paid => _settle(checkout, payer, paid),
    };
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
