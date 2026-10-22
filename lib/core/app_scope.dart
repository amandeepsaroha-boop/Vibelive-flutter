import 'package:flutter/widgets.dart';

import 'i18n/i18n.dart';
import 'theme/theme_controller.dart';

/// App-level controllers reachable from any widget:
/// `AppScope.of(context).locale.setLocale(const Locale('hi'))`.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.theme,
    required this.locale,
    required super.child,
  });

  final ThemeController theme;
  final LocaleController locale;

  static AppScope of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing above $context');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      theme != oldWidget.theme || locale != oldWidget.locale;
}
