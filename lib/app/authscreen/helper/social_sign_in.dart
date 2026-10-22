import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/utils/log.dart';
import 'auth_credentials.dart';

/// Google / Apple sign-in → Firebase ID token for the backend's social
/// exchange (RN `GoogleLogin` / `AppleLogin`). Each returns null when the
/// user closes the sheet: that is not an error.
///
/// Firebase and Google start only when a provider is tapped, so app launch
/// never pays for them.
abstract final class SocialSignIn {
  static Future<void>? _firebase;
  static Future<void>? _google;

  static Future<String?> google() async {
    await _ensureFirebase();
    await (_google ??= GoogleSignIn.instance
        .initialize(
          clientId: Platform.isIOS ? AuthCredentials.googleIosClientId : null,
          serverClientId: AuthCredentials.googleServerClientId,
        )
        .catchError((Object e) {
          _google = null;
          throw e;
        }));
    // Fresh account picker every time (RN signed out first too).
    await _quietly(GoogleSignIn.instance.signOut);
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('Google returned no ID token');
    return _firebaseToken(
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      ),
    );
  }

  /// iOS 13+ only; the button is hidden everywhere else.
  static Future<bool> appleAvailable() async {
    if (!Platform.isIOS) return false;
    try {
      return await SignInWithApple.isAvailable();
    } catch (_) {
      return false;
    }
  }

  static Future<String?> apple() async {
    await _ensureFirebase();
    // Apple signs the SHA-256 we send; Firebase checks it against the raw
    // value, so a stolen identity token can't be replayed.
    final rawNonce = _nonce();
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }
    final idToken = apple.identityToken;
    if (idToken == null) throw StateError('Apple returned no identity token');
    final credential = await FirebaseAuth.instance.signInWithCredential(
      AppleAuthProvider.credentialWithIDToken(
        idToken,
        rawNonce,
        AppleFullPersonName(
          givenName: apple.givenName,
          familyName: apple.familyName,
        ),
      ),
    );
    // Apple sends the name only on the very first authorization: keep it.
    final name = [
      apple.givenName,
      apple.familyName,
    ].whereType<String>().join(' ').trim();
    final user = credential.user;
    if (name.isNotEmpty && (user?.displayName ?? '').isEmpty) {
      await _quietly(() => user!.updateDisplayName(name));
    }
    return _firebaseToken(credential);
  }

  /// The backend session replaces the provider session: drop it.
  static Future<void> signOut() async {
    if (_firebase == null) return;
    await _quietly(FirebaseAuth.instance.signOut);
    if (_google != null) await _quietly(GoogleSignIn.instance.signOut);
  }

  /// Firebase already starts at boot (push layer); this reuses that app and
  /// only initialises it when boot could not.
  static Future<void> _ensureFirebase() =>
      _firebase ??= _firebaseApp().then<void>((_) {}).catchError((Object e) {
        _firebase = null; // retry on the next tap
        throw e;
      });

  static Future<FirebaseApp> _firebaseApp() async {
    if (Firebase.apps.isNotEmpty) return Firebase.app();
    try {
      return await Firebase.initializeApp(options: AuthCredentials.firebase);
    } on FirebaseException catch (e) {
      if (e.code == 'duplicate-app') return Firebase.app();
      rethrow;
    }
  }

  static Future<String> _firebaseToken(UserCredential credential) async {
    final token = await credential.user?.getIdToken(true);
    if (token == null) throw StateError('Firebase returned no ID token');
    return token;
  }

  static String _nonce() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      Log.d('SocialSignIn', e);
    }
  }
}
