import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/log.dart';
import 'checkout_models.dart';
import 'payu_api.dart';
import 'razorpay_api.dart';

/// Wallet top-up entry point: asks the backend which gateway is live and
/// routes to it (RN `payWalletRecharge`).
abstract final class RechargeApi {
  static const _tag = 'RechargeApi';

  /// `GET /payment-gateway/selection`.
  static Future<PaymentGatewaySelection> fetchGatewaySelection() async =>
      PaymentGatewaySelection.fromResponse(
        await ApiClient.get('/payment-gateway/selection'),
      );

  /// Creates the order on the selected gateway. A 409 means the selection
  /// changed meanwhile: re-read it and retry once.
  static Future<RechargeCheckout> startWalletRecharge(
    RechargeRequest request,
  ) async {
    if (!request.amount.isFinite || request.amount <= 0) {
      throw const ApiException(
        ApiErrorType.rejected,
        messageKey: 'payment:errors.invalid_amount',
      );
    }
    try {
      return await _start(await _activeGateway(), request);
    } on ApiException catch (e) {
      if (e.statusCode != 409) rethrow;
      Log.d(_tag, 'gateway mismatch (409), re-reading selection');
      return _start(await _activeGateway(), request);
    }
  }

  /// RN falls back to Razorpay when the selection can't be read, so a
  /// selection outage doesn't block top-ups.
  static Future<PaymentGateway> _activeGateway() async {
    try {
      return (await fetchGatewaySelection()).gateway;
    } on ApiException catch (e) {
      Log.w(_tag, 'gateway selection failed, using Razorpay: $e');
      return PaymentGateway.razorpay;
    }
  }

  static Future<RechargeCheckout> _start(
    PaymentGateway gateway,
    RechargeRequest request,
  ) async {
    switch (gateway) {
      case PaymentGateway.payu:
        return PayUApi.startCheckout(
          amount: request.amount,
          payer: request.payer,
        );
      case PaymentGateway.razorpay:
        final response = await RazorpayApi.initiateWalletRecharge(
          request.amount,
        );
        return RazorpayApi.buildCheckout(
          response: response,
          baseAmount: request.amount,
          payer: request.payer,
          description: request.description,
          appConfig: request.appConfig,
          gstPercent: request.gstPercent,
        );
    }
  }

  /// Best effort, never throws (RN `reportPaymentSuccess`).
  static Future<void> reportSuccess(RechargeReport report) => report.isPayU
      ? PayUApi.reportSuccess(report)
      : RazorpayApi.reportSuccess(report);

  /// Best effort, never throws (RN `reportPaymentFailure`).
  static Future<void> reportFailure(RechargeReport report) => report.isPayU
      ? PayUApi.reportFailure(report)
      : RazorpayApi.reportFailure(report);
}
