import 'dart:async';
import 'dart:convert';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../../core/network/strapi.dart';
import '../../../../core/utils/log.dart';
import 'checkout_outcome.dart';

/// How the Razorpay checkout ended.
sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

/// Paid; the ids still have to be verified by the backend.
class CheckoutPaid extends CheckoutOutcome {
  const CheckoutPaid({required this.paymentId, this.orderId, this.signature});

  final String? paymentId;
  final String? orderId;
  final String? signature;
}

/// The user closed the checkout (or picked an external wallet app). Nothing
/// is shown for it.
class CheckoutCancelled extends CheckoutOutcome {
  const CheckoutCancelled({
    this.code,
    this.description,
    this.end = CheckoutEnd.userDismissed,
  });

  final int? code;
  final String? description;

  /// Why it ended; null when it is not a lost payment (external wallet).
  final CheckoutEnd? end;
}

/// The gateway reported an error. [description] is Razorpay's own text.
class CheckoutFailed extends CheckoutOutcome {
  const CheckoutFailed({
    this.code,
    this.description,
    this.end = CheckoutEnd.paymentFailed,
  });

  final int? code;
  final String? description;
  final CheckoutEnd end;
}

/// Seam around the native checkout so tests can fake it. Set
/// [RazorpayGateway.instance] to a fake in tests.
abstract class RazorpayGateway {
  static RazorpayGateway instance = NativeRazorpayGateway();

  /// Opens the checkout with `RazorpayCheckout.toOptions()` and resolves when
  /// it closes.
  Future<CheckoutOutcome> open(Map<String, dynamic> options);
}

/// `razorpay_flutter`: one [Razorpay] instance per checkout, cleared when it
/// ends.
class NativeRazorpayGateway implements RazorpayGateway {
  static const _tag = 'Razorpay';

  @override
  Future<CheckoutOutcome> open(Map<String, dynamic> options) {
    final done = Completer<CheckoutOutcome>();
    final razorpay = Razorpay();
    void finish(CheckoutOutcome outcome) {
      if (done.isCompleted) return;
      razorpay.clear();
      done.complete(outcome);
    }

    razorpay
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
        finish(
          CheckoutPaid(
            paymentId: r.paymentId,
            orderId: r.orderId,
            signature: r.signature,
          ),
        );
      })
      ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
        final description = errorDescription(r.message);
        Log.d(_tag, 'checkout error ${r.code}: $description');
        final end = classifyCheckoutEnd(
          description: description,
          misconfigured:
              r.code == Razorpay.INVALID_OPTIONS ||
              r.code == Razorpay.INCOMPATIBLE_PLUGIN,
        );
        finish(
          isCancel(r.code, description) || end == CheckoutEnd.userDismissed
              ? CheckoutCancelled(
                  code: r.code,
                  description: description,
                  end: end,
                )
              : CheckoutFailed(
                  code: r.code,
                  description: description,
                  end: end,
                ),
        );
      })
      // Paid in another app: the wallet catches up on refresh.
      ..on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {
        finish(const CheckoutCancelled(end: null));
      });
    try {
      razorpay.open(options);
    } catch (e) {
      finish(CheckoutFailed(description: '$e', end: CheckoutEnd.failedToOpen));
    }
    return done.future;
  }

  /// RN treated a cancelled / closed / dismissed checkout as no-op.
  static bool isCancel(int? code, String? description) {
    if (code == Razorpay.PAYMENT_CANCELLED) return true;
    final d = (description ?? '').toLowerCase();
    return d.contains('cancelled') ||
        d.contains('closed') ||
        d.contains('dismissed');
  }

  /// The SDK sends either plain text or a JSON body
  /// (`{"error":{"description":…}}`).
  static String? errorDescription(String? message) {
    if (message == null || message.trim().isEmpty) return null;
    try {
      final body = jsonDecode(message);
      if (body is Map) {
        final error = body['error'];
        final text = error is Map
            ? J.str(error['description']) ?? J.str(error['reason'])
            : J.str(body['description']);
        if (text != null) return text;
      }
    } on FormatException {
      // plain text
    }
    return message;
  }
}
