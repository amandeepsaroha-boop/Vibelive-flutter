import 'package:flutter/widgets.dart';
import 'package:i18next/i18next.dart';

import '../storage/app_prefs.dart';

/// Translations live in `assets/i18n/<lang>/<namespace>.json`.
/// Each file name is an i18next namespace; `common` is searched by default,
/// so `context.t('ok')` == `context.t('common:ok')`.
abstract final class AppI18n {
  static const fallbackLocale = Locale('en');

  static const supportedLocales = <Locale>[Locale('en'), Locale('hi')];

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
    if (saved != null && AppI18n.isSupported(Locale(saved))) {
      return LocaleController(Locale(saved));
    }
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    return LocaleController(
      AppI18n.isSupported(device)
          ? Locale(device.languageCode)
          : AppI18n.fallbackLocale,
    );
  }

  Future<void> setLocale(Locale locale) async {
    if (!AppI18n.isSupported(locale) || locale == value) return;
    value = locale;
    await AppPrefs.setString(_prefsKey, locale.languageCode);
  }
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
