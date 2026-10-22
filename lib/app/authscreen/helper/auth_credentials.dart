import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

import '../../../core/config/env.dart';

/// Every credential and identifier sign-in and links use, in one place.
///
/// The Firebase values are public client identifiers (they ship inside
/// every build, as in the RN app's GoogleService-Info.plist and
/// google-services.json). Google client IDs come from `config/env.json`.
abstract final class AuthCredentials {
  // ── Google (Firebase project vibeos-fd05a) ─────────────────────────────

  /// Web client: Google issues the ID token for it, Firebase verifies it.
  static String get googleServerClientId => Env.googleWebClientId;

  /// iOS OAuth client; its reversed form is a URL scheme in Info.plist.
  static String get googleIosClientId => Env.googleIosClientId;

  // ── Firebase (FCM, and turning Google / Apple sign-in into an ID token)

  static FirebaseOptions get firebase => Platform.isIOS
      ? FirebaseOptions(
          apiKey: _iosApiKey,
          appId: '1:833208176078:ios:932f35a15c9f6998036f9f',
          messagingSenderId: _senderId,
          projectId: _projectId,
          storageBucket: _bucket,
          iosBundleId: 'com.angrymamba.vibelive',
          iosClientId: googleIosClientId,
        )
      : const FirebaseOptions(
          apiKey: _androidApiKey,
          appId: '1:833208176078:android:5466a8f22e8d8419036f9f',
          messagingSenderId: _senderId,
          projectId: _projectId,
          storageBucket: _bucket,
        );

  /// MUST equal `API_KEY` in `ios/Runner/GoogleService-Info.plist` (the plist
  /// the RN Xcode project shipped). The native default app is configured from
  /// that plist; Dart options with another key make `initializeApp` fail with
  /// `duplicate-app`.
  static const _iosApiKey = 'AIzaSyCFJdYwdJTwSyfhJaTcpr5DUojh3__1z8E';

  /// Same as `android/app/google-services.json`.
  static const _androidApiKey = 'AIzaSyBP4JOzuHibvlxN1p30t98Yc-DN74hNfsI';
  static const _senderId = '833208176078';
  static const _projectId = 'vibeos-fd05a';
  static const _bucket = 'vibeos-fd05a.firebasestorage.app';

  // ── Links ──────────────────────────────────────────────────────────────

  /// Share / referral links: https://vibelive.angrymamba.com/{slug}.
  static const webDomain = 'vibelive.angrymamba.com';

  /// `vibeexpoapp://` share links (same paths as [webDomain]).
  static const shareScheme = 'vibeexpoapp';

  /// `vibecalling://` campaign and admin-panel links.
  static const campaignScheme = 'vibecalling';

  /// Play Store package (install referrer, store links).
  static const playPackage = 'com.angrymamba.VibeLive';

  // ── Legal ──────────────────────────────────────────────────────────────

  static const termsUrl = 'https://angrymamba.com/terms';
  static const privacyUrl = 'https://angrymamba.com/privacy';
  static const guidelinesUrl = 'https://angrymamba.com/community-guidelines';
}
