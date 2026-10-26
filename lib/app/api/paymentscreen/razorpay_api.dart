import 'dart:convert';
import 'dart:math';

import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/utils/log.dart';
import 'billing_models.dart';
import 'checkout_models.dart';
import 'payment_json.dart';

/// Razorpay wallet top-up around the native checkout: create the order,
/// build the SDK options, verify the SDK result, report the outcome.
abstract final class RazorpayApi {
  static const _tag = 'RazorpayApi';

  /// `POST /razorpay/wallet-recharge/initiate` (older backends:
  /// `/razorpay/initiate`). Returns the order payload.
  static Future<JsonMap> initiateWalletRecharge(double amount) async {
    final data = {'amount': amount};
    dynamic body;
    try {
      body = await ApiClient.post(
        '/razorpay/wallet-recharge/initiate',
        data: data,
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 405) {
        throw paymentError(e, 'payment:errors.recharge_failed');
      }
      try {
        body = await ApiClient.post('/razorpay/initiate', data: data);
      } on ApiException {
        throw paymentError(e, 'payment:errors.recharge_failed');
      }
    }
    final payload = paymentData(body);
    // Validation failures (amount limits…) may come back as HTTP 200.
    if (J.str(payload['status']) == 'error' || payload['success'] == false) {
      throw ApiException(
        ApiErrorType.rejected,
        serverMessage: paymentMessage(payload),
        messageKey: 'payment:errors.recharge_failed',
        data: payload,
      );
    }
    return payload;
  }

  /// Turns an initiate [response] into checkout options (RN
  /// `makeRazorpayPayment`). The backend must have created the order: no
  /// client-side order creation (that needs the key secret).
  static RazorpayCheckout buildCheckout({
    required JsonMap response,
    required double baseAmount,
    required PayerInfo payer,
    required String description,
    JsonMap? appConfig,
    double gstPercent = GstConfig.defaultIgstRate,
  }) {
    final razorpayData = Strapi.map(response['razorpayData']) ?? const {};
    final orderId =
        J.str(response['orderId']) ??
        J.str(response['order_id']) ??
        J.str(response['id']) ??
        J.str(razorpayData['order_id']) ??
        J.str(razorpayData['id']);
    if (orderId == null) {
      throw ApiException(
        ApiErrorType.rejected,
        serverMessage: paymentMessage(response),
        messageKey: 'payment:errors.order_failed',
        data: response,
      );
    }

    final keyId =
        _firstStr(response, const [
          'keyId',
          'RazorPay_Id',
          'razorpay_id',
          'Razorpay_Id',
          'key',
          'razorpayKey',
        ]) ??
        _firstStr(razorpayData, const ['RazorPay_Id', 'key']) ??
        _firstStr(response, const ['key_id', 'razorpay_key_id']) ??
        keyFromAppConfig(appConfig) ??
        (Env.razorpayKeyId.isEmpty ? null : Env.razorpayKeyId);
    if (keyId == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: 'payment:errors.config_missing',
      );
    }

    final prefill = Strapi.map(response['prefill']) ?? const {};
    final checkout = Strapi.map(response['checkout']) ?? const {};
    final txnId =
        J.str(response['transactionId']) ??
        'RZP_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';

    return RazorpayCheckout(
      baseAmount: baseAmount,
      txnId: txnId,
      orderId: orderId,
      keyId: keyId,
      amountInPaise: _amountInPaise(response, baseAmount, gstPercent),
      currency: J.str(response['currency']) ?? 'INR',
      description: J.str(checkout['description']) ?? description,
      // RN prefilled "User" when nameless; left empty (and editable) instead
      // so no English reaches the checkout. Top-up requires a name anyway.
      prefillName: (J.str(prefill['name']) ?? payer.name ?? '').trim(),
      prefillEmail: (J.str(prefill['email']) ?? payer.email ?? '').trim(),
      prefillContact: cleanMobile(J.str(prefill['contact']) ?? payer.phone),
      notes: {
        'userId': J.str(payer.id) ?? '',
        'userDocumentId': payer.documentId ?? '',
        'txnId': txnId,
      },
      response: response,
    );
  }

  /// Public key id from `/app-config` (RN `extractRazorpayKeyFromConfig`).
  /// The key secret it also carries is deliberately never read.
  static String? keyFromAppConfig(JsonMap? appConfig) {
    final node = Strapi.map(appConfig);
    if (node == null) return null;
    return _firstStr(node, const [
      'RazorPay_Id',
      'Razorpay_Id',
      'razorpay_id',
      'razorPay_Id',
      'RazorPay_ID',
      'razorpay_key_id',
      'razorpay_key',
      'razorPayId',
      'RazorPayId',
    ]);
  }

  /// Indian mobile for the checkout prefill: digits only, `91`/`0` prefix
  /// dropped. A 10-digit number not starting 6–9 gets a leading 9, since
  /// Razorpay rejects it otherwise (RN rule).
  static String cleanMobile(String? raw) {
    var digits = (raw ?? '').trim().replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('91') && digits.length == 12) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    if (digits.length == 10 && !RegExp(r'^[6-9]').hasMatch(digits)) {
      digits = '9${digits.substring(1)}';
    }
    return digits;
  }

  /// `POST /razorpay/payments/verify`.
  static Future<JsonMap> verifyPayment(RazorpayPayment payment) async =>
      paymentData(
        await ApiClient.post(
          '/razorpay/payments/verify',
          data: {
            'razorpay_payment_id': payment.paymentId,
            'razorpay_order_id': ?payment.orderId,
            'razorpay_signature': ?payment.signature,
          },
        ),
      );

  /// `GET /razorpay/payments/:transactionId/status`.
  static Future<JsonMap> fetchPaymentStatus(String transactionId) async =>
      paymentData(
        await ApiClient.get(
          '/razorpay/payments/${Uri.encodeComponent(transactionId)}/status',
          // The caller polls; no extra transport retries.
          retry: false,
        ),
      );

  /// Verify, and if the verify call fails, poll the status endpoint (RN
  /// `verifyRazorpayPaymentWithFallback`). An unconfirmed payment ends as
  /// pending, never as a false failure.
  static Future<RazorpayVerification> verifyWithFallback(
    RazorpayPayment payment, {
    int maxPolls = 4,
    Duration pollDelay = const Duration(milliseconds: 2500),
  }) async {
    final txnId = payment.transactionId;
    try {
      final result = await verifyPayment(payment);
      var status = _status(result, const ['status']);
      if (status.isEmpty && J.boolean(result['success'])) status = 'success';
      return _isPaid(status)
          ? RazorpayVerification(
              VerificationOutcome.success,
              status: status,
              data: result,
            )
          : RazorpayVerification(
              VerificationOutcome.failed,
              serverMessage: paymentMessage(result),
              data: result,
            );
    } on ApiException catch (e) {
      Log.w(_tag, 'verify failed: $e');
      if (txnId == null || txnId.isEmpty) {
        return const RazorpayVerification(VerificationOutcome.failed);
      }
    }

    for (var attempt = 1; attempt <= maxPolls; attempt++) {
      await Future<void>.delayed(pollDelay);
      try {
        final res = await fetchPaymentStatus(txnId);
        final status = _status(res, const ['paymentStatus', 'status']);
        if (_isPaid(status)) {
          return RazorpayVerification(
            VerificationOutcome.success,
            status: status,
            recovered: true,
            data: res,
          );
        }
      } on ApiException catch (e) {
        Log.w(_tag, 'status poll $attempt/$maxPolls failed: $e');
      }
    }
    return const RazorpayVerification(VerificationOutcome.pending);
  }

  /// First of [keys] on the payload, then on its nested `data`, lower-cased.
  static String _status(JsonMap payload, List<String> keys) {
    final nested = payload['data'];
    final value =
        _firstStr(payload, keys) ??
        (nested is Map
            ? _firstStr(Map<String, dynamic>.from(nested), keys)
            : null);
    return (value ?? '').toLowerCase();
  }

  /// `POST /razorpay/success` (older backends: `/razorpay/verify`).
  /// Best effort like RN: verification already settled the payment.
  static Future<void> reportSuccess(RechargeReport report) async {
    final payload = {
      ..._reportBase(report),
      'razorpay_order_id': report.razorpayOrderId ?? '',
      'razorpay_signature': report.razorpaySignature ?? '',
      'status': 'success',
    };
    try {
      await ApiClient.post('/razorpay/success', data: payload);
    } on ApiException catch (e) {
      if (e.statusCode != 404) {
        Log.w(_tag, 'success report failed: $e');
        return;
      }
      try {
        await ApiClient.post('/razorpay/verify', data: payload);
      } on ApiException catch (e) {
        Log.w(_tag, 'success report (verify route) failed: $e');
      }
    }
  }

  /// `POST /razorpay/failure`. Best effort like RN.
  static Future<void> reportFailure(RechargeReport report) async {
    final reason = report.failureReason;
    final payload = {
      ..._reportBase(report),
      'status': 'failure',
      'error': switch (reason) {
        final Map<dynamic, dynamic> m =>
          J.str(m['description']) ?? jsonEncode(m),
        final String s when s.isNotEmpty => s,
        _ => 'Payment failed',
      },
    };
    try {
      await ApiClient.post('/razorpay/failure', data: payload);
    } on ApiException catch (e) {
      Log.w(_tag, 'failure report failed: $e');
    }
  }

  // Backend field values, not UI copy.
  static JsonMap _reportBase(RechargeReport r) => {
    'txnid': r.txnId ?? r.razorpayPaymentId ?? '',
    'razorpay_payment_id': r.razorpayPaymentId ?? '',
    'amount': r.amount ?? '',
    'firstname': r.payer.name ?? 'User',
    'email': r.payer.email ?? '',
    'phone': r.payer.phone ?? '',
    'productinfo': 'Wallet Recharge',
    'udf1': J.str(r.payer.id) ?? '',
  };

  static bool _isPaid(String status) =>
      status == 'success' || status == 'already_processed';

  /// Paise for the SDK. A response amount under 100 is taken as rupees (RN
  /// heuristic); without one, the base amount plus GST.
  static int _amountInPaise(
    JsonMap response,
    double baseAmount,
    double gstPercent,
  ) {
    final raw = response['amount'];
    final present = raw != null && raw != 0 && raw != '' && raw != false;
    if (!present) {
      final total = GstBreakdown.of(baseAmount, percent: gstPercent).total;
      return ((total > 0 ? total : baseAmount) * 100).round();
    }
    final value = J.number(raw);
    if (value == null || !value.isFinite) {
      throw ApiException(
        ApiErrorType.parse,
        messageKey: 'payment:errors.order_failed',
        data: response,
      );
    }
    return value < 100 && baseAmount >= 1
        ? (value * 100).round()
        : value.round();
  }

  /// `POST /razorpay/payments/:transactionId/abandon`. Never throws (RN):
  /// the person already left checkout, and the backend sweeper catches
  /// anything this misses.
  static Future<void> reportCheckoutAbandoned({
    required String transactionId,
    required String classification,
    int? errorCode,
    String? description,
  }) async {
    if (transactionId.isEmpty) return;
    try {
      await ApiClient.post(
        '/razorpay/payments/${Uri.encodeComponent(transactionId)}/abandon',
        data: {
          'classification': classification,
          'errorCode': ?errorCode,
          'description': ?description,
        },
      );
    } on ApiException catch (e) {
      Log.w(_tag, 'abandon report failed (non-fatal): $e');
    }
  }

  static String? _firstStr(JsonMap map, List<String> keys) {
    for (final key in keys) {
      final v = J.str(map[key]);
      if (v != null) return v;
    }
    return null;
  }
}
