import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/analytics/analytics.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_store.dart';
import '../../../api/paymentscreen/billing_models.dart';
import '../../../api/paymentscreen/checkout_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/transaction_api.dart';
import 'checkout_outcome.dart';
import 'razorpay_gateway.dart';
import 'web_checkout.dart';

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
  Future<RechargeCheckout> createOrder({
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
    if (checkout is PayUCheckout && (checkout.payuUrl ?? '').isEmpty) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'payment:errors.payu_failed',
      );
    }
    return checkout;
  }

  /// Opens the checkout for [checkout] and settles it. Null when the user
  /// closed the checkout (RN: nothing shown); [onAbandoned] then runs when
  /// that was the person's own choice (the exit-intent offer). [web] opens
  /// the WebView checkout: PayU, and Razorpay when the native checkout could
  /// not open (RN fallback). Without it those end as a failure.
  Future<TopUpStatus?> pay(
    RechargeCheckout checkout,
    PayerInfo payer, {
    VoidCallback? onAbandoned,
    WebCheckoutOpener? web,
  }) async {
    _logInitiate(checkout);
    if (checkout is PayUCheckout) return _payU(checkout, payer, web);
    final order = checkout as RazorpayCheckout;
    final options = order.toOptions(image: await CheckoutLogo.dataUri());
    final gateway = _gateway ?? RazorpayGateway.instance;
    final outcome = await gateway.open(options);
    final (
      CheckoutEnd? end,
      int? code,
      String? description,
    ) = switch (outcome) {
      CheckoutPaid() => (null, null, null),
      CheckoutCancelled(:final end, :final code, :final description) => (
        end,
        code,
        description,
      ),
      CheckoutFailed(:final end, :final code, :final description) => (
        end,
        code,
        description,
      ),
    };
    if (outcome is CheckoutPaid) return _settle(order, payer, outcome);
    // RN classifies first, then branches on the class (not on the code).
    switch (end) {
      case null: // paid in an external wallet: the wallet catches up
        return null;
      case CheckoutEnd.userDismissed:
        _logEnd(order, end, code, description);
        onAbandoned?.call();
        return null;
      case CheckoutEnd.failedToOpen:
        // Not reported as abandoned or failed: the WebView retry may still
        // succeed, and the sweeper marks it if nothing lands.
        _logEnd(order, end, code, description);
        if (web == null) {
          return const TopUpStatus(
            TopUpResult.failure,
            messageKey: 'payment:errors.recharge_failed',
          );
        }
        return _fromWeb(
          order,
          payer,
          await web(
            WebCheckoutRequest(html: WebCheckoutPages.razorpay(options)),
          ),
        );
      case CheckoutEnd.paymentFailed:
        return _fail(order, payer, message: description ?? 'Payment failed');
    }
  }

  /// RN PayU: the hosted form in the WebView, the outcome from its return
  /// URL or from polling the transaction.
  Future<TopUpStatus?> _payU(
    PayUCheckout checkout,
    PayerInfo payer,
    WebCheckoutOpener? web,
  ) async {
    if (web == null) {
      return const TopUpStatus(
        TopUpResult.failure,
        messageKey: 'payment:errors.gateway_unavailable',
      );
    }
    final end = await web(
      WebCheckoutRequest(
        html: WebCheckoutPages.payu(checkout.payuUrl!, checkout.payuData),
        poll: () => _pollPayU(checkout.txnId),
      ),
    );
    return _fromWeb(checkout, payer, end);
  }

  /// RN `startPolling`: the newest transactions, looking for this one.
  static Future<WebCheckoutEnd?> _pollPayU(String txnId) async {
    final uid = SessionStore.instance.value.userDocumentId;
    if (uid == null || txnId.isEmpty) return null;
    final rows = await TransactionApi.fetchPage(uid, size: 10);
    for (final t in rows) {
      final ref = t.reference ?? '';
      if (ref != txnId && !ref.contains(txnId)) continue;
      if (t.isSuccess) return const WebCheckoutPaid();
      if (t.isFailure) return const WebCheckoutFailed('Payment failed');
    }
    return null;
  }

  Future<TopUpStatus?> _fromWeb(
    RechargeCheckout checkout,
    PayerInfo payer,
    WebCheckoutEnd end,
  ) async => switch (end) {
    // RN: closing the WebView just closes it (no abandon, no offer).
    WebCheckoutClosed() => null,
    WebCheckoutFailed(:final reason) => _fail(checkout, payer, message: reason),
    WebCheckoutPaid(:final paymentId, :final orderId, :final signature) =>
      checkout is RazorpayCheckout
          ? await _settle(
              checkout,
              payer,
              CheckoutPaid(
                paymentId: paymentId,
                orderId: orderId,
                signature: signature,
              ),
            )
          : _succeed(checkout, payer),
  };

  /// RN `logInitiatePayment` (after the order, before checkout opens):
  /// Meta AddedPaymentInfo + InitiatedCheckout, and `initiate_payment`.
  void _logInitiate(RechargeCheckout checkout) {
    final amount = checkout.baseAmount;
    final orderId = switch (checkout) {
      RazorpayCheckout(:final orderId) when orderId.isNotEmpty => orderId,
      _ => checkout.txnId,
    };
    final method = checkout.gateway == PaymentGateway.payu
        ? 'payu'
        : 'razorpay';
    Analytics.meta('fb_mobile_add_payment_info', {
      'payment_method': method,
      'currency': 'INR',
      'amount': amount,
    });
    Analytics.meta('fb_mobile_initiated_checkout', {
      'content_id': orderId,
      'content_type': 'wallet_recharge',
      'currency': 'INR',
      'amount': amount,
    }, valueToSum: amount);
    Analytics.log('initiate_payment', {
      'amount': amount > 0 ? amount : null,
      'payment_method': method,
      'order_id': orderId,
    });
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
      _logSuccess(checkout, paymentId);
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

  /// PayU paid (no verification step: RN reported it straight away).
  TopUpStatus _succeed(RechargeCheckout checkout, PayerInfo payer) {
    _logSuccess(checkout, checkout.txnId);
    unawaited(
      _reportSuccess(
        RechargeReport(
          gateway: checkout.gateway,
          payer: payer,
          txnId: checkout.txnId,
          amount: checkout.baseAmount,
        ),
      ),
    );
    return const TopUpStatus(TopUpResult.success);
  }

  /// RN `logPaymentSuccess`: Meta Purchase + `payment_success`, once per
  /// transaction.
  void _logSuccess(RechargeCheckout checkout, String paymentId) {
    final id = paymentId.isNotEmpty ? paymentId : checkout.txnId;
    final method = checkout.gateway == PaymentGateway.payu
        ? 'payu'
        : 'razorpay';
    Analytics.metaPurchase(checkout.baseAmount, {
      'transaction_id': id,
      'payment_method': method,
    });
    Analytics.logOnce('payment_success_$id', 'payment_success', {
      'amount': checkout.baseAmount,
      'payment_method': method,
      'currency': 'INR',
    });
  }

  TopUpStatus _fail(
    RechargeCheckout checkout,
    PayerInfo payer, {
    String? message,
    String? messageKey,
  }) {
    final reason = message ?? _reasonText[messageKey] ?? 'Payment failed';
    // RN `logPaymentFailed`, once per transaction.
    Analytics.logOnce('payment_failed_${checkout.txnId}', 'payment_failed', {
      'reason': reason,
      'payment_method': checkout.gateway == PaymentGateway.payu
          ? 'payu'
          : 'razorpay',
    });
    unawaited(
      _reportFailure(
        RechargeReport(
          gateway: checkout.gateway,
          payer: payer,
          txnId: checkout.txnId,
          amount: checkout.baseAmount,
          failureReason: reason,
        ),
      ),
    );
    return TopUpStatus(
      TopUpResult.failure,
      message: message,
      messageKey: messageKey,
    );
  }

  /// RN's English reason for the backend / analytics when the dialog shows
  /// a translated one.
  static const _reasonText = {
    'payment:errors.verification_failed':
        'Payment verification could not be completed.',
  };

  void dispose() => verifying.dispose();
}
