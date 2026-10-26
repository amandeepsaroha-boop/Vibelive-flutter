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
  // Google OAuth client ids are public (they also sit in
  // google-services.json and Info.plist), so they default here: Google
  // sign-in never breaks on a run or build started without env.json.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '833208176078-de0s7kisp7tvsis5li0acc9d4hpjv46o.apps.googleusercontent.com',
  );
  static const String googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue:
        '833208176078-3dc9iovvbt3cclt67cgrilnt1v3ck8aa.apps.googleusercontent.com',
  );
  static const String razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');
}
