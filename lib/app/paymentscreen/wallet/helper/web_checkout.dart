import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How a WebView checkout ended (RN WalletScreen's WebView modal).
sealed class WebCheckoutEnd {
  const WebCheckoutEnd();
}

/// Paid. The Razorpay ids are set for Razorpay Checkout; PayU has none (its
/// transaction id identifies the payment).
class WebCheckoutPaid extends WebCheckoutEnd {
  const WebCheckoutPaid({this.paymentId, this.orderId, this.signature});
  final String? paymentId;
  final String? orderId;
  final String? signature;
}

class WebCheckoutFailed extends WebCheckoutEnd {
  const WebCheckoutFailed(this.reason);
  final String reason;
}

/// Closed without paying (RN: just closes, no offer).
class WebCheckoutClosed extends WebCheckoutEnd {
  const WebCheckoutClosed();
}

/// What the WebView page loads, and (PayU) how to ask the backend whether
/// the payment landed meanwhile.
@immutable
class WebCheckoutRequest {
  const WebCheckoutRequest({required this.html, this.poll});

  final String html;

  /// Checked every [pollEvery] for [pollFor] (RN PayU polling); null while
  /// nothing is known yet.
  final Future<WebCheckoutEnd?> Function()? poll;

  static const pollEvery = Duration(seconds: 5);
  static const pollFor = Duration(minutes: 5);
}

/// Opens the WebView page; the wallet screen supplies it.
typedef WebCheckoutOpener =
    Future<WebCheckoutEnd> Function(WebCheckoutRequest request);

/// RN `payment.service` HTML pages and URL rules.
abstract final class WebCheckoutPages {
  /// The JS channel the pages post to (RN `window.ReactNativeWebView`).
  static const channel = 'ReactNativeWebView';

  /// RN `generateRazorpayHtml`: Razorpay Checkout.js, results posted back.
  static String razorpay(Map<String, dynamic> options) {
    final json = jsonEncode(options).replaceAll('</', r'<\/');
    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; padding: 0; background: #0f172a; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #ffffff; }
    .spinner { width: 48px; height: 48px; border: 4px solid rgba(255, 255, 255, 0.15); border-top-color: #561de2; border-radius: 50%; animation: spin 0.8s linear infinite; }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
    .text { margin-top: 16px; font-size: 14px; color: rgba(255, 255, 255, 0.7); font-weight: 500; }
  </style>
</head>
<body>
  <div class="spinner"></div>
  <div class="text">Opening Razorpay Secure Checkout...</div>
  <script>
    (function() {
      function post(type, payload) {
        if (window.$channel && window.$channel.postMessage) {
          window.$channel.postMessage(JSON.stringify({ type: type, payload: payload }));
        }
      }
      try {
        var baseOptions = $json;
        baseOptions.handler = function(response) {
          post('RAZORPAY_SUCCESS', {
            razorpay_payment_id: response.razorpay_payment_id,
            razorpay_order_id: response.razorpay_order_id,
            razorpay_signature: response.razorpay_signature
          });
        };
        baseOptions.modal = {
          ondismiss: function() {
            post('RAZORPAY_CANCELLED', { reason: 'User cancelled payment checkout' });
          }
        };
        var rzp = new Razorpay(baseOptions);
        rzp.on('payment.failed', function(response) {
          post('RAZORPAY_FAILURE', response.error || { description: 'Payment failed' });
        });
        window.onload = function() {
          try { rzp.open(); } catch (e) {
            post('RAZORPAY_FAILURE', { description: e.message || 'Failed to open Razorpay' });
          }
        };
      } catch (err) {
        post('RAZORPAY_FAILURE', { description: err.message || 'Razorpay checkout initialisation error' });
      }
    })();
  </script>
</body>
</html>''';
  }

  /// RN `generatePayUHtml`: the hosted form, posted once on load.
  static String payu(String url, Map<String, dynamic> data) {
    final fields = StringBuffer();
    data.forEach((key, value) {
      if (value == null) return;
      fields.write(
        '<input type="hidden" name="${_escape(key)}" value="${_escape('$value')}" />',
      );
    });
    return '<html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
        '<body><form id="payuForm" method="POST" action="${_escape(url)}">$fields</form>'
        '<script>window.onload = function() { if (!window.__payuSubmitted) { '
        "window.__payuSubmitted = true; document.getElementById('payuForm').submit(); } };"
        '</script></body></html>';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;');

  /// A message from the page's JS channel → its end (null: ignore).
  static WebCheckoutEnd? fromMessage(String message) {
    try {
      final data = jsonDecode(message);
      if (data is! Map) return null;
      final payload = data['payload'] is Map ? data['payload'] as Map : null;
      String? text(String key) {
        final v = payload?[key];
        return v == null || '$v'.trim().isEmpty ? null : '$v';
      }

      return switch (data['type']) {
        'RAZORPAY_SUCCESS' => WebCheckoutPaid(
          paymentId: text('razorpay_payment_id'),
          orderId: text('razorpay_order_id'),
          signature: text('razorpay_signature'),
        ),
        'RAZORPAY_FAILURE' => WebCheckoutFailed(
          text('description') ?? 'Payment failed',
        ),
        'RAZORPAY_CANCELLED' => const WebCheckoutClosed(),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  /// RN `onShouldStartLoadWithRequest`: gateway return URLs end the
  /// checkout (the page is not loaded); anything else loads.
  static WebCheckoutEnd? fromUrl(String url) {
    final payu = url.contains('payu');
    if (url.contains('/api/payu/success') ||
        url.contains('payu.in/success') ||
        (payu &&
            (url.contains('status=000') || url.contains('status=success')))) {
      return const WebCheckoutPaid();
    }
    if (url.contains('/api/payu/failure') ||
        url.contains('payu.in/failure') ||
        (payu &&
            (url.contains('status=failure') ||
                url.contains('status=failed')))) {
      return WebCheckoutFailed(url);
    }
    if (url.contains('/api/razorpay/success') ||
        url.contains('razorpay_success')) {
      return const WebCheckoutPaid();
    }
    if (url.contains('/api/razorpay/failure') ||
        url.contains('razorpay_failure')) {
      return WebCheckoutFailed(url);
    }
    return null;
  }
}

/// RN `image: APP_ICON_BASE64`: the checkout's logo, the same app icon as a
/// data URI (read once).
abstract final class CheckoutLogo {
  static String? _cached;

  static Future<String?> dataUri() async {
    if (_cached != null) return _cached;
    try {
      final bytes = await rootBundle.load('assets/images/brand/app_icon.png');
      return _cached =
          'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
    } catch (_) {
      return null;
    }
  }
}
