/// Why a Razorpay checkout ended without a payment (RN `checkout-outcome.js`).
enum CheckoutEnd {
  /// The person closed checkout, or abandoned inside the UPI app.
  userDismissed('user_dismissed'),

  /// Checkout never got far enough for the person to make a choice.
  failedToOpen('checkout_failed_to_open'),

  /// A real gateway failure: declined, timed out, malformed request.
  paymentFailed('payment_failed');

  const CheckoutEnd(this.wire);

  /// The value the backend and analytics use.
  final String wire;
}

/// Substrings that mean the person chose to stop.
const _dismissalMarkers = [
  'cancel',
  'closed',
  'dismiss',
  'back press',
  'user_cancel',
];

/// RN checked the code first, so an SDK or configuration failure (which
/// also reports the cancel code with no description) was logged as "cancelled
/// by user". The description is the only signal that carries intent, so it
/// is read first; only a bare code means checkout failed to open.
/// [misconfigured] is the plugin's "invalid options / incompatible" signal.
/// [cancelCode]: razorpay_flutter's own PAYMENT_CANCELLED. Unlike RN's
/// module it is only sent when the person closed checkout, often with no
/// text (or "undefined"): that is a dismissal, not a failure to open.
CheckoutEnd classifyCheckoutEnd({
  required String? description,
  bool misconfigured = false,
  bool cancelCode = false,
}) {
  var text = (description ?? '').trim();
  if (text == 'undefined' || text == 'null') text = '';
  final lower = text.toLowerCase();
  if (text.isNotEmpty && _dismissalMarkers.any(lower.contains)) {
    return CheckoutEnd.userDismissed;
  }
  if (cancelCode && text.isEmpty && !misconfigured) {
    return CheckoutEnd.userDismissed;
  }
  if (text.isEmpty || misconfigured) return CheckoutEnd.failedToOpen;
  return CheckoutEnd.paymentFailed;
}
