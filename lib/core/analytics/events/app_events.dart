import '../analytics.dart';

/// App-level events: launch, notifications (non-call delivery, every tap),
/// links, the update notice (Firebase + Meta). Catalog:
/// docs/analytics_events.md.
abstract final class AppEvents {
  // ── Launch ─────────────────────────────────────────────────────────────

  /// Once per cold start, when the splash knows where the user goes.
  /// [nextScreen]: the screen name it routes to (`home_discover`, `login`,
  /// `onboarding_age_gate`…); [onCall]: a call opened the app.
  static void appLaunched({
    required bool signedIn,
    String? role,
    String? nextScreen,
    bool onCall = false,
  }) => Analytics.logOnce('app_launched', 'app_launched', {
    'signed_in': signedIn,
    'role': role,
    'next_screen': nextScreen,
    'launch_source': onCall ? 'call' : 'normal',
  });

  // ── Notifications ──────────────────────────────────────────────────────

  /// A non-call push reached the app. [kind]: campaign, wallet,
  /// verification, milestone, general; [foreground]: app in front.
  static void pushReceived({
    required String kind,
    required String type,
    String? campaignId,
    required bool foreground,
    required bool hasDeeplink,
  }) => Analytics.log('push_received', {
    'kind': kind,
    'type': type,
    'campaign_id': campaignId,
    'foreground': foreground,
    'has_deeplink': hasDeeplink,
  });

  /// The app drew a notification banner for a push.
  static void pushShown({
    required String kind,
    required String type,
    String? campaignId,
    required bool background,
  }) => Analytics.log('push_shown', {
    'kind': kind,
    'type': type,
    'campaign_id': campaignId,
    'background': background,
  });

  /// A notification was tapped (any kind, calls included). [destination]:
  /// campaign, wallet, verification, referral, call_history (missed call),
  /// incoming_call, ongoing_call, callback, route, link, none.
  static void pushOpened({
    required String destination,
    required String type,
    String? campaignId,
    String? screen,
    required bool hasDeeplink,
  }) => Analytics.log('push_opened', {
    'destination': destination,
    'type': type,
    'campaign_id': campaignId,
    'screen': screen,
    'has_deeplink': hasDeeplink,
  });

  // ── Links ──────────────────────────────────────────────────────────────

  /// The OS handed the app a link. [source]: `scheme` (vibecalling://),
  /// `web` (https://…/app/…), `share` (a share / profile / referral link);
  /// [parked]: it waits for sign-in / Home.
  static void deeplinkReceived({
    required String source,
    required bool signedIn,
    required bool parked,
    bool hasReferral = false,
  }) => Analytics.log('deeplink_received', {
    'source': source,
    'signed_in': signedIn,
    'parked': parked,
    'has_referral': hasReferral,
  });

  /// A link (or a notification's destination) actually opened a screen.
  /// [source]: `push`, `campaign` (link from outside), `share`, `route`
  /// (a notification's own destination); [linkType]: the share path or
  /// campaign screen; [fallbackHome]: the link was unusable, Home opened.
  static void deeplinkOpened({
    required String screen,
    required String source,
    String? linkType,
    bool fallbackHome = false,
    bool external = false,
  }) => Analytics.log('deeplink_opened', {
    'screen': screen,
    'source': source,
    'link_type': linkType,
    'fallback_home': fallbackHome,
    'external': external,
  });

  /// Android Play install referrer read (once per install).
  static void installReferrer({required bool hasCode, String? intent}) =>
      Analytics.logOncePersisted('install_referrer', 'install_referrer', {
        'has_code': hasCode,
        'intent': intent,
      });

  // ── Update notice ──────────────────────────────────────────────────────

  static void updatePromptShown({required String version, required bool forced}) =>
      Analytics.log('update_prompt_shown', {
        'version': version,
        'forced': forced,
      });

  static void updateTapped({String? version, bool? forced}) =>
      Analytics.log('update_tapped', {'version': version, 'forced': forced});

  static void updateDismissed({required String version}) =>
      Analytics.log('update_dismissed', {'version': version});
}
