import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/utils/log.dart';
import 'checkout_models.dart';
import 'payment_json.dart';

/// PayU wallet top-up: the backend signs the form, the app posts it in a
/// WebView, then reports the outcome.
abstract final class PayUApi {
  static const _tag = 'PayUApi';

  /// `POST /payu/initiate` (RN `makePaymentPayU`).
  static Future<PayUCheckout> startCheckout({
    required double amount,
    required PayerInfo payer,
  }) async {
    final uid = payer.id ?? payer.documentId ?? '';
    final dynamic body;
    try {
      body = await ApiClient.post(
        '/payu/initiate',
        data: {
          'amount': amount,
          'userId': uid,
          'phone': payer.phone ?? '',
          'email': payer.email ?? '',
          'udf1': '$uid',
        },
      );
    } on ApiException catch (e) {
      throw paymentError(e, 'payment:errors.payu_failed');
    }

    final response = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    if (response['status'] != 'success') {
      throw ApiException(
        ApiErrorType.rejected,
        serverMessage: paymentMessage(response),
        messageKey: 'payment:errors.payu_failed',
        data: response,
      );
    }
    final payuData = response['payuData'];
    final data = payuData is Map ? Map<String, dynamic>.from(payuData) : null;
    final txnId = J.str(data?['txnid']);
    if (data == null || txnId == null || J.str(data['hash']) == null) {
      throw ApiException(
        ApiErrorType.parse,
        messageKey: 'payment:errors.payu_failed',
        data: response,
      );
    }
    return PayUCheckout(
      baseAmount: amount,
      txnId: txnId,
      payuData: data,
      payuUrl: J.str(response['payuUrl']),
    );
  }

  /// `POST /payu/success`. Best effort like RN; skipped without a txn id or
  /// amount.
  static Future<void> reportSuccess(RechargeReport report) async {
    final payu = report.payuResponse ?? const {};
    final hasTxn = report.txnId != null || J.str(payu['txnid']) != null;
    final hasAmount = report.amount != null || J.str(payu['amount']) != null;
    if (!hasTxn || !hasAmount) return;
    await _post('/payu/success', {..._base(report), 'status': 'success'});
  }

  /// `POST /payu/failure`. Best effort like RN; skipped without a txn id.
  static Future<void> reportFailure(RechargeReport report) async {
    final payu = report.payuResponse ?? const {};
    if (report.txnId == null && J.str(payu['txnid']) == null) return;
    final reason = report.failureReason;
    await _post('/payu/failure', {
      ..._base(report),
      'status': 'failure',
      'error': reason == null || reason is String || reason is Map
          ? reason
          : '$reason',
    });
  }

  static Future<void> _post(String path, JsonMap payload) async {
    try {
      await ApiClient.post(path, data: payload);
    } on ApiException catch (e) {
      Log.w(_tag, '$path report failed: $e');
    }
  }

  // Backend field values, not UI copy.
  static JsonMap _base(RechargeReport r) {
    final payu = r.payuResponse ?? const {};
    return {
      'txnid': r.txnId ?? J.str(payu['txnid']) ?? '',
      'amount': J.str(payu['amount']) ?? r.amount ?? '',
      'firstname': J.str(payu['firstname']) ?? r.payer.name ?? 'User',
      'email': J.str(payu['email']) ?? r.payer.email ?? '',
      'phone': J.str(payu['phone']) ?? r.payer.phone ?? '',
      'productinfo': J.str(payu['productinfo']) ?? 'Wallet Recharge',
      'hash': J.str(payu['hash']) ?? '',
      'udf1': J.str(r.payer.id) ?? '',
    };
  }
}
