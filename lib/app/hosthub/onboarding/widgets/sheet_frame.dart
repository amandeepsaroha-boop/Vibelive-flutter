import 'package:flutter/material.dart';

import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/keyboard_inset.dart';
import '../helper/host_palette.dart';

/// Opens a bottom sheet of the flow (keyboard-safe, max 80% tall).
/// [name]: the sheet's analytics screen name.
Future<T?> showHostSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  required String name,
  Map<String, dynamic>? titleVariables,
}) => showModalBottomSheet<T>(
  context: context,
  routeSettings: ScreenTracker.sheet(name),
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: AppColors.transparent,
  elevation: 0,
  barrierColor: AppColors.blackA(0.45),
  builder: (_) => KeyboardInset(
    child: HostSheetFrame(
      title: title,
      titleVariables: titleVariables,
      child: child,
    ),
  ),
);

/// Rounded sheet with a grab handle and a title.
class HostSheetFrame extends StatelessWidget {
  const HostSheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.titleVariables,
  });

  /// i18n key.
  final String title;
  final Map<String, dynamic>? titleVariables;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.isDark ? AppColors.darkSurface : AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.ms)),
        ),
        child: SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: 16.ms),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(top: 10.ms, bottom: 14.ms),
                  decoration: BoxDecoration(
                    color: p.track,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.ms, 0, 20.ms, 12.ms),
                child: CText(
                  title,
                  variables: titleVariables,
                  size: 20,
                  weight: FontWeight.w800,
                  color: p.text,
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
