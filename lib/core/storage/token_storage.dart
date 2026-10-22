import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Auth tokens in Keychain / Keystore.
///
/// iOS uses `first_unlock` so tokens stay readable while the device is locked
/// (a VoIP push can wake the app on a locked phone).
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  /// Mirrors the access token to native code that makes calls while Dart
  /// may not run (iOS CallKit decline / answer: `VibeCallNetwork`). Set by
  /// the call layer at boot; called with null on [clear]. Never awaited
  /// into the token write and never allowed to fail it.
  static void Function(String? accessToken)? onAccessTokenChanged;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<String?> readAccessToken() => _read(_accessTokenKey);
  Future<String?> readRefreshToken() => _read(_refreshTokenKey);

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    _mirror(accessToken);
  }

  /// Never throws: a keychain that is unavailable (locked VoIP boot) must
  /// not fail a sign-out or a session restore.
  Future<void> clear() async {
    for (final key in const [_accessTokenKey, _refreshTokenKey]) {
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    }
    _mirror(null);
  }

  /// Whether a token is stored: null when that is unknown because the store
  /// could not be read (keychain unavailable before the first unlock, a
  /// keystore error). Unknown is never "no token".
  Future<bool?> hasTokens() async {
    try {
      for (final key in const [_accessTokenKey, _refreshTokenKey]) {
        if ((await _storage.read(key: key))?.isNotEmpty == true) return true;
      }
      return false;
    } catch (_) {
      return null;
    }
  }

  static void _mirror(String? token) {
    try {
      onAccessTokenChanged?.call(token);
    } catch (_) {}
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }
}
