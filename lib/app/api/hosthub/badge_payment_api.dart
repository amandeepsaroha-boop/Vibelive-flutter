import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import '../paymentscreen/checkout_models.dart';
import '../paymentscreen/payment_json.dart';
import '../paymentscreen/razorpay_api.dart';

/// Where a badge-fee payment starts: already settled, or a Razorpay order.
sealed class BadgePaymentStart {
  const BadgePaymentStart();
}

final class BadgeAlreadyPaid extends BadgePaymentStart {
  const BadgeAlreadyPaid();
}

final class BadgeCheckout extends BadgePaymentStart {
  const BadgeCheckout(this.checkout);
  final RazorpayCheckout checkout;
}

/// Verification Badge fee through Razorpay (RN `payExpertVerification`).
/// The backend creates the order; the app never uses the key secret (RN's
/// client-side order fallback is deliberately not ported).
abstract final class HostBadgePaymentApi {
  static const description = 'Host Verification Fees';

  /// `POST /razorpay/expert-verifications/:id/initiate`.
  static Future<BadgePaymentStart> start({
    required String verificationId,
    required double fee,
    required PayerInfo payer,
    JsonMap? appConfig,
  }) async {
    final body = await ApiClient.post(
      '/razorpay/expert-verifications/${Uri.encodeComponent(verificationId)}'
      '/initiate',
      data: const {},
    );
    final response = paymentData(body);
    if (J.str(response['status']) == 'already_processed' ||
        J.boolean(response['alreadyPaid'])) {
      return const BadgeAlreadyPaid();
    }
    return BadgeCheckout(
      RazorpayApi.buildCheckout(
        response: response,
        baseAmount: fee,
        payer: payer,
        description: description,
        appConfig: appConfig,
      ),
    );
  }

  /// What RN posted to `/expert-verification/payment-response` after a
  /// Razorpay success.
  static JsonMap paymentResponse({
    required String? paymentId,
    required String? orderId,
    required String? signature,
    required double fee,
    required PayerInfo payer,
  }) => {
    'txnid': paymentId ?? 'RZP_VERIF_${DateTime.now().millisecondsSinceEpoch}',
    'razorpay_payment_id': paymentId ?? '',
    'razorpay_order_id': orderId ?? '',
    'razorpay_signature': signature ?? '',
    'status': 'success',
    'amount': fee,
    'firstname': payer.name ?? '',
    'email': payer.email ?? '',
    'phone': payer.phone ?? '',
    'productinfo': description,
    'udf1': J.str(payer.id) ?? '',
  };
}
