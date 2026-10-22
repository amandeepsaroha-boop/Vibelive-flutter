# Vibe Live (Flutter)

Flutter rewrite of the Vibe Live app: bundle id `com.angrymamba.vibelive`, iOS and Android. It uses the same Strapi backend as the React Native app (`../VibeCallingFrontEnd`).

## Run

```sh
cp config/env.example.json config/env.json   # once; fill DEFAULT_API_TOKEN (see RN src/core/api/client.js)
flutter pub get
flutter run --dart-define-from-file=config/env.json
flutter run --dart-define-from-file=config/env.json --dart-define=API_URL=http://10.0.2.2:1337   # local backend
```

VS Code: the two launch configs in `.vscode/launch.json` already pass the env file.

Regenerate the launcher icons and native splash after changing them:

```sh
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## Structure

```
lib/
  main.dart                  bootstrap: error handler, prefs, session, network status, app
  core/                      shared infrastructure only, no feature code
    config/env.dart              build-time config (API_URL, DEFAULT_API_TOKEN, …)
    network/api_client.dart      the only HTTP client (auth, 401 refresh, retries)
    network/api_exception.dart   the only error type the API layer throws
    network/strapi.dart          Strapi unwrapping + media URL helpers (RN xnode/xlist/media)
    query/                       fquery cache, hooks, disk-persisted queries
    session/session_store.dart   logged-in user + expert, sign in/out
    theme/                       colors (RN Colors.js), dark/light theme, ThemeController
    i18n/i18n.dart               i18next setup, LocaleController, context.t()
    utils/scale.dart             moderateScale / scale / verticalScale (RN responsive.js)
    router/app_router.dart       routes (same paths as RN), navigator keys
  app/
    api/<feature>/           API + query hooks per feature (see docs/api_conventions.md)
    component/               reusable UI kit (below)
    banner/                  TopWarnBar, OfflineBanner
    authscreen/ splashscreen/ homescreen/ client/ callscreen/ hosthub/
    listingflow/ paymentscreen/ resourcesscreen/ navbar/{topbar,bottombar}/
assets/
  i18n/<lang>/<namespace>.json   en + hi
  images/  sounds/               copied from the RN app (AppImages / AppSounds constants)
```

## Rules of thumb

- **Text.** Every visible string goes through i18n. Pass keys to components: `CText('home:title')`, `CButton(title: 'actions.continue')`. Server data uses `CText.raw(name)`.
- **Sizes.** Use `moderateScale(n)` or `n.ms`, which match the RN app's 375x812 base. `CText` ignores the OS font-size setting.
- **Colors.** Theme-dependent colors come from `context.colors` (for example `accent` = lime in dark mode, purple in light). Fixed colors come from `AppColors`, `BrandColors`, `StatusColors` and the other classes in `core/theme/app_colors.dart`.
- **Data.** Screens are `HookWidget`s that call `use…` hooks from `lib/app/api/<feature>/…_queries.dart` and render with `QueryView`.
- **Errors.** API failures arrive as `ApiException`.
  - `QueryView` shows retry screens.
  - `CAlert.error(e)` and `CToast.error(e)` show messages: the backend's readable message if it sent one, otherwise our translated copy.
  - Uncaught errors are logged by `AppErrorHandler`.

## Components (`lib/app/component`)

| Component | RN source | Notes |
| --- | --- | --- |
| `CText` / `CText.raw` | `CFont` | variants h1/h2/sub/caption/body, no OS text scaling |
| `CButton` | `Button` | primary/secondary/outline/ghost/small/cta, loading, 600 ms tap debounce |
| `CInput` | `InputBox` | mobile (+91, digits only)/email/password/name/referral, error text |
| `CAlert` | `VibeAlertModal` | `show` / `confirm` / `error`; works without a context, never stacks duplicates |
| `CBackButton` | `BackButton` | chevron-back; custom handler also bound to Android back |
| `CToast` | — | snackbar, `show` / `error` |
| `AppLogo` | `AppLogo` | in-app wordmark |
| `GlassCard` | `GlassCard` | blurred card |
| `VibeBackground` | `VibeBackground` | screen fill |
| `VerificationBadge`, `InfluencerBadge` | `VerificationBadge` | lime decagram with check/crown; shimmer pill |
| `ImagePreviewModal` | `ImagePreviewModal` | drag to close; actions run after the modal closes |
| `CImage`, `CAvatar` | — / `avatarLetter`, `avatarColor` | cached, decoded at display size |
| `QueryView`, `CLoader`, `CStateView` | — | loading / error + retry / empty |
| `Pressable` | `TouchableOpacity` | dims on press |

## Translations

- **Namespaces.** Each JSON file in `assets/i18n/<lang>/` is a namespace: `context.t('banner:offline')`. Keys in `common` need no prefix: `context.t('actions.ok')`.
- **Syntax.** Variables use `{{name}}`; plurals use `key` and `key_plural` with `count:`.
- **Adding a language.** Create its folder, list it in `pubspec.yaml`, add it to `AppI18n.supportedLocales`, and add it to `CFBundleLocalizations` in `ios/Runner/Info.plist`.

## Login and links (`lib/app/authscreen/`)

The screens are `login_screen.dart`, `login_widgets.dart` and `terms_screen.dart`. All the logic lives in `helper/`:

| File | Job |
| --- | --- |
| `login_controller.dart` | email / phone OTP, auto-verify, resend timer, referral capture and validation, Google / Apple, first-time terms consent, post-login routing |
| `auth_navigation.dart` | `nextAuthRoute()`: login → 18+ gate → language step → Home (shared with the splash) |
| `social_sign_in.dart` | Google / Apple → Firebase ID token. Firebase starts only when a provider is tapped. |
| `auth_credentials.dart` | Firebase app config, Google client IDs, link domain and schemes, legal URLs |
| `deep_links.dart` | listens for links (cold and warm), parks them until sign-in / Home, Play install referrer |
| `link_parser.dart` | share / referral / install-referrer parsing, `shareLink()` builder |
| `campaign_links.dart` | `vibecalling://` admin presets, in-app browser URL rules |
| `terms_consent.dart` | per user + provider + terms version acceptance |

**Handled links:**
- `https://vibelive.angrymamba.com/{handler|code}?r=r|i` (verified App Links / Universal Links)
- `vibeexpoapp://…`
- `vibecalling://…`

The router never sees these links (`FlutterDeepLinkingEnabled` / `flutter_deeplinking_enabled` are off). Home must call `DeepLinks.instance.markAppReady()` and read `DeepLinks.instance.openUser`.

**Native setup still needed outside the repo:**
- **Firebase console:** register the debug and release SHA-1 of the Android signing key for `com.angrymamba.VibeLive`.
- **Apple Developer:** enable Sign in with Apple and Associated Domains for `com.angrymamba.vibelive`. The RN app already uses both.

## Not set up yet

Agora, Firebase/FCM, CallKit/PushKit, social sign-in SDKs, Razorpay/PayU checkout and ringtone playback all need native setup and come with their screens. The ringtone and coin sound files are already bundled, and copied into `android/app/src/main/res/raw`.
# Vibelive-flutter
