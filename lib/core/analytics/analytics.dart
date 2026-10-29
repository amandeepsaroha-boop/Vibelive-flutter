import 'dart:async';

import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../storage/app_prefs.dart';
import '../utils/log.dart';

/// Meta user data for advanced matching (hashed by the SDK on device).
@immutable
class AnalyticsUserData {
  const AnalyticsUserData({
    this.email,
    this.phone,
    this.firstName,
    this.gender,
    this.dateOfBirth,
    this.city,
    this.state,
    this.country = 'in',
  });

  final String? email;

  /// Digits with the country code (`919876543210`).
  final String? phone;
  final String? firstName;

  /// `m` / `f`.
  final String? gender;

  /// `YYYYMMDD`.
  final String? dateOfBirth;
  final String? city;
  final String? state;
  final String? country;
}

/// The single seam for product analytics: every event goes to Firebase
/// Analytics AND Meta (Facebook) App Events (RN `shared/lib/analytics.js`).
///
/// Event names live in the typed catalogs under `events/` (one file per
/// area); screens are logged by `ScreenTracker`. The full list for the
/// marketing team is `docs/analytics_events.md`.
///
/// Sending never throws and never blocks: a missing SDK (tests, Firebase
/// not ready) only loses the event.
abstract final class Analytics {
  static final _meta = FacebookAppEvents();

  /// Keys already logged by [logOnce] in this app session.
  static final _once = <String>{};

  static const _oncePrefix = 'analytics_once_';

  /// Tests: sees every event (name, cleaned params) before it is sent.
  @visibleForTesting
  static void Function(String event, Map<String, Object> params)? debugSink;

  /// After Firebase is up (before `runApp`). Collection is switched on
  /// explicitly: the iOS GoogleService-Info.plist carries the legacy
  /// `IS_ANALYTICS_ENABLED = false`.
  static Future<void> init() async {
    await _guard(
      () => FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true),
    );
    // Install / launch / session events come from the native Meta SDK
    // (RN `Settings.setAutoLogAppEventsEnabled(true)`).
    await _guard(() => _meta.setAutoLogAppEventsEnabled(true));
    await _guard(() => _meta.setAdvertiserIdCollectionEnabled(true));
  }

  // ── Events ─────────────────────────────────────────────────────────────

  /// [event] to Firebase and Meta. Keep names snake_case, at most 40
  /// characters, starting with a letter, and off Firebase's reserved list.
  static void log(String event, [Map<String, Object?> params = const {}]) {
    assert(_validName(event), 'Bad analytics event name: $event');
    final clean = sanitize(params);
    Log.d('Analytics', '$event $clean');
    debugSink?.call(event, clean);
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

  /// RN `logEventOncePersisted`: once per install for [key] (milestones
  /// such as `sign_up` or `first_call_completed`). True when it was sent.
  static bool logOncePersisted(
    String key,
    String event, [
    Map<String, Object?> params = const {},
  ]) {
    if (!_once.add('persisted:$key')) return false;
    if (AppPrefs.getString('$_oncePrefix$key') != null) return false;
    unawaited(AppPrefs.setString('$_oncePrefix$key', '1'));
    log(event, params);
    return true;
  }

  /// Whether [logOncePersisted] already went out for [key] on this install.
  static bool wasLoggedOnce(String key) =>
      _once.contains('persisted:$key') ||
      AppPrefs.getString('$_oncePrefix$key') != null;

  /// A screen (page, tab, sheet or step). Firebase's own `screen_view`;
  /// Meta gets a custom `screen_view` with the same name (RN parity).
  static void screen(String name, [Map<String, Object?> params = const {}]) {
    final clean = sanitize({'screen_name': name, ...params});
    Log.d('Analytics', 'screen $name');
    debugSink?.call('screen_view', clean);
    unawaited(
      _guard(() => _meta.logEvent(name: 'screen_view', parameters: clean)),
    );
    final extra = Map.of(clean)..remove('screen_name');
    unawaited(
      _guard(
        () => FirebaseAnalytics.instance.logScreenView(
          screenName: name,
          screenClass: name,
          parameters: extra.isEmpty ? null : _firebaseParams(extra),
        ),
      ),
    );
  }

  // ── Meta standard events (Firebase gets its own call site event) ───────

  /// A Meta-only event (`fb_mobile_*` standard events), with its value to
  /// sum.
  static void meta(
    String event,
    Map<String, Object?> params, {
    double? valueToSum,
  }) {
    final clean = sanitize(params);
    Log.d('Analytics', 'meta $event $clean');
    debugSink?.call('meta:$event', clean);
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
    debugSink?.call('meta:purchase', {...clean, 'amount': amount});
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

  /// A Firebase-only event (recommended events such as `purchase`, whose
  /// Meta twin is a standard event sent separately).
  static void firebase(String event, Map<String, Object?> params) {
    assert(_validName(event), 'Bad analytics event name: $event');
    final clean = sanitize(params);
    Log.d('Analytics', 'firebase $event $clean');
    debugSink?.call('firebase:$event', clean);
    unawaited(
      _guard(
        () => FirebaseAnalytics.instance.logEvent(
          name: event,
          parameters: _firebaseParams(clean),
        ),
      ),
    );
  }

  // ── Who ────────────────────────────────────────────────────────────────

  /// Ties later events to [userId] on both platforms (null clears it), plus
  /// Meta advanced matching from [data].
  static Future<void> setUser(String? userId, {AnalyticsUserData? data}) async {
    Log.d('Analytics', 'user $userId');
    if (userId == null) {
      await _guard(() => FirebaseAnalytics.instance.setUserId(id: null));
      await _guard(_meta.clearUserID);
      await _guard(_meta.clearUserData);
      return;
    }
    await _guard(() => FirebaseAnalytics.instance.setUserId(id: userId));
    await _guard(() => _meta.setUserID(userId));
    final d = data;
    if (d == null) return;
    await _guard(
      () => _meta.setUserData(
        email: _clip(d.email?.trim().toLowerCase()),
        phone: _clip(d.phone),
        firstName: _clip(d.firstName?.trim().toLowerCase()),
        gender: _clip(d.gender),
        dateOfBirth: _clip(d.dateOfBirth),
        city: _clip(d.city?.trim().toLowerCase()),
        state: _clip(d.state?.trim().toLowerCase()),
        country: _clip(d.country),
        externalId: userId,
      ),
    );
  }

  /// A Firebase user property (name at most 24 characters, value at most
  /// 36). Meta has no user properties: the values ride on the events.
  static Future<void> userProperty(String name, String? value) => _guard(
    () => FirebaseAnalytics.instance.setUserProperty(
      name: name,
      value: value == null || value.isEmpty
          ? null
          : (value.length > 36 ? value.substring(0, 36) : value),
    ),
  );

  // ── Plumbing ───────────────────────────────────────────────────────────

  /// RN `sanitizeParams`: drops null, empty / "null" / "undefined" text and
  /// non-finite numbers; numbers stay numbers, booleans become
  /// "true" / "false", everything else is text. At most 25 parameters.
  static Map<String, Object> sanitize(Map<String, Object?> params) {
    final out = <String, Object>{};
    params.forEach((key, value) {
      if (value == null || out.length >= 25) return;
      if (value is num) {
        if (value.isFinite) out[key] = value;
        return;
      }
      if (value is bool) {
        out[key] = value ? 'true' : 'false';
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

  static String? _clip(String? v) => v == null || v.isEmpty ? null : v;

  static final _namePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  /// Firebase drops these silently (they are its own automatic events).
  static const _reserved = {
    'ad_activeview', 'ad_click', 'ad_exposure', 'ad_impression', 'ad_query',
    'ad_reward', 'adunit_exposure', 'app_background', 'app_clear_data',
    'app_exception', 'app_remove', 'app_store_refund', 'app_update',
    'app_upgrade', 'error', 'first_open', 'first_visit', 'in_app_purchase',
    'notification_dismiss', 'notification_foreground', 'notification_open',
    'notification_receive', 'os_update', 'screen_view', 'session_start',
    'user_engagement',
  };

  static bool _validName(String event) =>
      _namePattern.hasMatch(event) &&
      !_reserved.contains(event) &&
      !event.startsWith('firebase_') &&
      !event.startsWith('google_') &&
      !event.startsWith('ga_');

  static Future<void> _guard(Future<void> Function() send) async {
    try {
      await send();
    } catch (e) {
      Log.d('Analytics', 'not sent: $e');
    }
  }
}
