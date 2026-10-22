import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';

/// Status-bar icons that stay readable on the screen behind them (RN root
/// `<StatusBar style={dark ? 'light' : 'dark'} />`). Wrap a whole screen:
/// without a region the bar keeps the previous screen's icons (e.g. white
/// icons from the always-dark login on a light page).
class ThemedStatusBar extends StatelessWidget {
  const ThemedStatusBar({super.key, required this.child, this.darkBackground});

  /// Forces the style; null follows the theme.
  final bool? darkBackground;
  final Widget child;

  /// Light icons over a dark background, dark icons over a light one.
  static SystemUiOverlayStyle styleFor({required bool darkBackground}) =>
      (darkBackground ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: AppColors.transparent);

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: styleFor(darkBackground: darkBackground ?? context.colors.isDark),
    child: child,
  );
}
