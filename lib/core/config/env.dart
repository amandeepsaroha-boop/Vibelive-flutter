/// Build-time config, injected with `--dart-define-from-file=config/env.json`
/// (already wired in `.vscode/launch.json`). Single values can be overridden,
/// e.g. `--dart-define=API_URL=http://10.0.2.2:1337`.
abstract final class Env {
  static const String _rawApiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://manageapps.angrymamba.com',
  );

  /// Same as the RN app: host only, no trailing slash and no `/api` suffix.
  /// [ApiClient] prefixes relative paths with `/api`.
  static final String apiBaseUrl = _rawApiUrl
      .replaceAll(RegExp(r'/+$'), '')
      .replaceAll(RegExp(r'/api$'), '');

  static const String appPlatform = String.fromEnvironment(
    'APP_PLATFORM',
    defaultValue: 'vibe_os',
  );

  /// App-level token the backend expects on pre-login endpoints
  /// (OTP, session-auth, app-config, …) when no user token exists.
  static const String defaultApiToken = String.fromEnvironment(
    'DEFAULT_API_TOKEN',
  );

  static const String agoraAppId = String.fromEnvironment('AGORA_APP_ID');
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );
  static const String razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
}
