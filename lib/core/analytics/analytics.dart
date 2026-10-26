import '../utils/log.dart';

/// The single seam for product analytics events (RN `shared/lib/analytics.js`).
///
/// The app has no analytics SDK yet, so this only logs in debug. Call it at
/// the same points RN dispatches an event; wiring a real backend (Firebase,
/// Meta) later is a change to this file only.
abstract final class Analytics {
  static void log(String event, [Map<String, Object?> params = const {}]) {
    final clean = <String, Object?>{
      for (final e in params.entries)
        if (e.value != null) e.key: e.value,
    };
    Log.d('Analytics', '$event $clean');
  }
}
