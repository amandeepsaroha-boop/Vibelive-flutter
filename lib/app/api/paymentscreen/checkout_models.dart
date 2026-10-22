import '../../../core/network/strapi.dart';
import 'payment_json.dart';

/// The user paying, as sent to the gateways (RN `userData`).
class PayerInfo {
  const PayerInfo({
    this.id,
    this.documentId,
    this.name,
    this.email,
    this.phone,
  });

  /// From the session user (`SessionState.user`) or a profile map.
  factory PayerInfo.fromUser(JsonMap? user) => PayerInfo(
    id: user?['id'],
    documentId: J.str(user?['documentId']),
    name: J.str(user?['name']),
    email: J.str(user?['email']),
    phone:
        J.str(user?['mobile']) ??
        J.str(user?['phone']) ??
        J.str(user?['contact']),
  );

  /// Numeric Strapi id, sent as-is (RN keeps its JSON type).
  final Object? id;
  final String? documentId;
  final String? name;
  final String? email;
  final String? phone;
}

enum PaymentGateway { razorpay, payu }

/// `GET /payment-gateway/selection`.
class PaymentGatewaySelection {
  const PaymentGatewaySelection(this.raw);

  final JsonMap raw;

  factory PaymentGatewaySelection.fromResponse(dynamic body) =>
      PaymentGatewaySelection(paymentData(body));

  /// RN rule: only an explicit "razorpay" selects Razorpay; any other value
  /// (including none) means PayU.
  PaymentGateway get gateway {
    final value = J.str(raw['paymentGateway']) ?? J.str(raw['gateway']) ?? '';
    return value.trim().toLowerCase() == 'razorpay'
        ? PaymentGateway.razorpay
        : PaymentGateway.payu;
  }

  String? get platform => J.str(raw['platform']);
}

/// Input of a wallet top-up.
class RechargeRequest {
  const RechargeRequest({
    required this.amount,
    required this.payer,
    required this.description,
    this.appConfig,
  });

  /// Rupees, before GST.
  final double amount;
  final PayerInfo payer;

  /// Razorpay checkout description, already localized by the caller.
  final String description;

  /// `/app-config` body, only read for the Razorpay key when the initiate
  /// response has none.
  final JsonMap? appConfig;

  RechargeRequest withAppConfig(JsonMap? config) => RechargeRequest(
    amount: amount,
    payer: payer,
    description: description,
    appConfig: config,
  );
}

/// What the UI needs to open the gateway chosen by the backend.
sealed class RechargeCheckout {
  const RechargeCheckout({required this.baseAmount, required this.txnId});

  /// Rupees the user asked for, before GST.
  final double baseAmount;

  /// Our transaction reference, used for polling and reporting.
  final String txnId;

  PaymentGateway get gateway;
}

/// PayU hosted form: POST [payuData] as hidden fields to [payuUrl].
class PayUCheckout extends RechargeCheckout {
  const PayUCheckout({
    required super.baseAmount,
    required super.txnId,
    required this.payuData,
    this.payuUrl,
  });

  final JsonMap payuData;

  /// Null: use app-config `payment_gateway_url_frontend`.
  final String? payuUrl;

  @override
  PaymentGateway get gateway => PaymentGateway.payu;
}

/// Everything the Razorpay checkout SDK needs ([toOptions]).
class RazorpayCheckout extends RechargeCheckout {
  const RazorpayCheckout({
    required super.baseAmount,
    required super.txnId,
    required this.orderId,
    required this.keyId,
    required this.amountInPaise,
    required this.currency,
    required this.description,
    required this.prefillName,
    required this.prefillEmail,
    required this.prefillContact,
    required this.notes,
    required this.response,
  });

  final String orderId;

  /// Public key id only. The key secret never belongs in the app.
  final String keyId;
  final int amountInPaise;
  final String currency;
  final String description;
  final String prefillName;
  final String prefillEmail;
  final String prefillContact;
  final Map<String, String> notes;

  /// Raw initiate response.
  final JsonMap response;

  /// Merchant name and brand colour shown by the checkout (RN values).
  static const merchantName = 'Vibe Live';
  static const themeColor = '#561de2';

  @override
  PaymentGateway get gateway => PaymentGateway.razorpay;

  /// `RazorpayCheckout.open` options. [image] is the merchant logo (RN sends
  /// a base64 app icon).
  JsonMap toOptions({String? image}) => {
    'description': description,
    'image': ?image,
    'currency': currency,
    'key': keyId,
    'amount': amountInPaise,
    'name': merchantName,
    'order_id': orderId,
    'prefill': {
      'email': prefillEmail,
      'contact': prefillContact,
      'name': prefillName,
    },
    'readonly': {
      'email': prefillEmail.isNotEmpty,
      'contact': prefillContact.isNotEmpty,
      'name': prefillName.isNotEmpty,
    },
    'theme': {'color': themeColor},
    'retry': {'enabled': true, 'max_count': 4},
    'modal': {'confirm_close': true},
    'notes': notes,
  };
}

/// Razorpay SDK success payload, plus our [transactionId] for status
/// recovery when verification drops.
class RazorpayPayment {
  const RazorpayPayment({
    required this.paymentId,
    this.orderId,
    this.signature,
    this.transactionId,
  });

  /// From the SDK's success map (`razorpay_payment_id`, …).
  factory RazorpayPayment.fromSdk(
    Map<dynamic, dynamic> data, {
    String? transactionId,
    String? fallbackOrderId,
  }) => RazorpayPayment(
    paymentId: J.str(data['razorpay_payment_id']) ?? '',
    orderId: J.str(data['razorpay_order_id']) ?? fallbackOrderId,
    signature: J.str(data['razorpay_signature']),
    transactionId: transactionId,
  );

  final String paymentId;
  final String? orderId;
  final String? signature;
  final String? transactionId;
}

enum VerificationOutcome {
  success,

  /// Verification dropped and status recovery didn't confirm: the money is
  /// most likely taken, so the UI must not show a failure.
  pending,
  failed,
}

class RazorpayVerification {
  const RazorpayVerification(
    this.outcome, {
    this.status,
    this.recovered = false,
    this.serverMessage,
    this.data,
  });

  final VerificationOutcome outcome;

  /// `success` or `already_processed` on success.
  final String? status;

  /// Confirmed by the status poll, not by the verify call.
  final bool recovered;

  /// Backend message of a failed verification, if any.
  final String? serverMessage;
  final JsonMap? data;

  bool get isSuccess => outcome == VerificationOutcome.success;

  /// Copy for pending / failed.
  String get messageKey => switch (outcome) {
    VerificationOutcome.pending => 'payment:verification.pending',
    _ => 'payment:errors.verification_failed',
  };
}

/// Result of a top-up checkout, reported to the backend (RN
/// `reportPaymentSuccess` / `reportPaymentFailure`).
class RechargeReport {
  const RechargeReport({
    required this.gateway,
    required this.payer,
    this.txnId,
    this.amount,
    this.razorpayPaymentId,
    this.razorpayOrderId,
    this.razorpaySignature,
    this.payuResponse,
    this.failureReason,
  });

  final PaymentGateway gateway;
  final PayerInfo payer;
  final String? txnId;
  final num? amount;
  final String? razorpayPaymentId;
  final String? razorpayOrderId;
  final String? razorpaySignature;

  /// PayU form/response fields (`txnid`, `amount`, `hash`, …).
  final JsonMap? payuResponse;

  /// Failure only: a message, or the gateway's error map.
  final Object? failureReason;

  bool get isPayU => gateway == PaymentGateway.payu || payuResponse != null;
}
