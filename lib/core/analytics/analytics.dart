import 'dart:async';

import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import '../utils/log.dart';

/// The single seam for product analytics events (RN `shared/lib/analytics.js`):
/// every event goes to Firebase Analytics and Meta (Facebook) App Events.
///
/// RN sent a few events to Meta twice (a direct Meta call plus the shared
/// dispatch); here each event reaches each backend once. Sending never
/// throws: a missing SDK (tests, no Firebase app) only loses the event.
abstract final class Analytics {
  static final _meta = FacebookAppEvents();

  /// Keys already logged by [logOnce] in this app session.
  static final _once = <String>{};

  static void log(String event, [Map<String, Object?> params = const {}]) {
    final clean = sanitize(params);
    Log.d('Analytics', '$event $clean');
    unawaited(_guard(() => _meta.logEvent(name: event, parameters: clean)));
    unawaited(
      _guard(
        () => FirebaseAnalytics.instance.logEvent(
          name: event,
          parameters: _firebaseParams(clean),
        ),
      ),
    );
  }

  /// RN `logEventOnce`: [event] at most once per app session for [key]
  /// (e.g. one `payment_success` per transaction).
  static void logOnce(
    String key,
    String event, [
    Map<String, Object?> params = const {},
  ]) {
    if (!_once.add(key)) return;
    log(event, params);
  }

  /// A Meta-only standard event (`fb_mobile_*`), with its value to sum.
  static void meta(
    String event,
    Map<String, Object?> params, {
    double? valueToSum,
  }) {
    final clean = sanitize(params);
    Log.d('Analytics', 'meta $event $clean');
    unawaited(
      _guard(
        () => _meta.logEvent(
          name: event,
          parameters: clean,
          valueToSum: valueToSum,
        ),
      ),
    );
  }

  /// Meta's Purchase event (RN `AppEventsLogger.logPurchase`).
  static void metaPurchase(double amount, Map<String, Object?> params) {
    final clean = sanitize(params);
    Log.d('Analytics', 'meta purchase $amount $clean');
    unawaited(
      _guard(
        () => _meta.logPurchase(
          amount: amount,
          currency: 'INR',
          parameters: clean,
        ),
      ),
    );
  }

  /// RN `sanitizeParams`: drops null, empty / "null" / "undefined" text and
  /// non-finite numbers; numbers stay numbers, everything else is text.
  static Map<String, Object> sanitize(Map<String, Object?> params) {
    final out = <String, Object>{};
    params.forEach((key, value) {
      if (value == null) return;
      if (value is num) {
        if (value.isFinite) out[key] = value;
        return;
      }
      final text = '$value'.trim();
      if (text.isEmpty || text == 'null' || text == 'undefined') return;
      out[key] = text;
    });
    return out;
  }

  /// Firebase caps text parameters at 100 characters.
  static Map<String, Object> _firebaseParams(Map<String, Object> clean) => {
    for (final e in clean.entries)
      e.key: e.value is String && (e.value as String).length > 100
          ? (e.value as String).substring(0, 100)
          : e.value,
  };

  static Future<void> _guard(Future<void> Function() send) async {
    try {
      await send();
    } catch (e) {
      Log.d('Analytics', 'not sent: $e');
    }
  }
}
