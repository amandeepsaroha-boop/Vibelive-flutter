import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:i18next/i18next.dart';

import '../analytics/analytics.dart';
import '../storage/app_prefs.dart';

/// A language the app is translated into. Its name is never translated:
/// each is shown in its own script, with the English name to help find it.
@immutable
class AppLanguage {
  const AppLanguage(this.code, this.nativeName, this.englishName);

  /// The `assets/i18n/<code>` folder and the locale's language code.
  final String code;
  final String nativeName;
  final String englishName;

  Locale get locale => Locale(code);
}

/// Translations live in `assets/i18n/<lang>/<namespace>.json`.
/// Each file name is an i18next namespace; `common` is searched by default,
/// so `context.t('ok')` == `context.t('common:ok')`.
abstract final class AppI18n {
  static const fallbackLocale = Locale('en');

  /// Every language, in the order the language picker lists them. A new
  /// one needs its `assets/i18n/<code>/` folder (all namespaces) and a
  /// pubspec asset entry; `test/core/i18n_files_test.dart` checks both.
  static const languages = <AppLanguage>[
    AppLanguage('en', 'English', 'English'),
    AppLanguage('hi', 'हिन्दी', 'Hindi'),
    AppLanguage('bn', 'বাংলা', 'Bengali'),
    AppLanguage('mr', 'मराठी', 'Marathi'),
    AppLanguage('ta', 'தமிழ்', 'Tamil'),
    AppLanguage('gu', 'ગુજરાતી', 'Gujarati'),
    AppLanguage('ur', 'اردو', 'Urdu'),
    AppLanguage('kn', 'ಕನ್ನಡ', 'Kannada'),
    AppLanguage('or', 'ଓଡ଼ିଆ', 'Odia'),
  ];

  static final List<Locale> supportedLocales = [
    for (final l in languages) l.locale,
  ];

  /// The language of [locale] (English when not one of ours).
  static AppLanguage languageOf(Locale locale) => languages.firstWhere(
    (l) => l.code == locale.languageCode,
    orElse: () => languages.first,
  );

  static final LocalizationsDelegate<I18Next> delegate =
      I18NextLocalizationDelegate(
        locales: supportedLocales,
        dataSource: AssetBundleLocalizationDataSource(
          bundlePath: 'assets/i18n',
        ),
        options: const I18NextOptions(
          fallbackNamespaces: ['common'],
          fallbackLocales: [fallbackLocale],
          // Flutter text is not HTML: "Tom & Jerry" must not become "&amp;".
          escapeValue: false,
        ),
      );

  static bool isSupported(Locale locale) =>
      supportedLocales.any((l) => l.languageCode == locale.languageCode);
}

/// Current app language, persisted across launches.
class LocaleController extends ValueNotifier<Locale> {
  LocaleController(super.value);

  static const _prefsKey = 'app_locale';

  /// Saved language > device language (if supported) > English.
  /// Synchronous: [AppPrefs] is already loaded.
  factory LocaleController.load() {
    final saved = AppPrefs.getString(_prefsKey);
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    final locale = saved != null && AppI18n.isSupported(Locale(saved))
        ? Locale(saved)
        : AppI18n.isSupported(device)
        ? Locale(device.languageCode)
        : AppI18n.fallbackLocale;
    _reportLanguage(locale);
    return LocaleController(locale);
  }

  Future<void> setLocale(Locale locale) async {
    if (!AppI18n.isSupported(locale) || locale == value) return;
    value = locale;
    _reportLanguage(locale);
    await AppPrefs.setString(_prefsKey, locale.languageCode);
  }

  /// Firebase user property `app_language` (en, hi, bn…).
  static void _reportLanguage(Locale locale) =>
      unawaited(Analytics.userProperty('app_language', locale.languageCode));
}

extension I18nContext on BuildContext {
  I18Next get i18n => I18Next.of(this)!;

  /// i18next-style lookup: `context.t('home:greeting', variables: {'name': n})`.
  String t(
    String key, {
    Map<String, dynamic>? variables,
    int? count,
    String? context,
  }) => i18n.t(key, variables: variables, count: count, context: context);
}
