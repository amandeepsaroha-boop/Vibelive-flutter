import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import 'c_text.dart';

enum CToastVariant { success, error, info }

/// Short non-blocking message at the bottom (no context needed).
///
/// ```dart
/// CToast.show('client:profile_saved', variant: CToastVariant.success);
/// CToast.error(e);
/// ```
abstract final class CToast {
  static void show(
    String message, {
    Map<String, dynamic>? variables,
    CToastVariant variant = CToastVariant.info,
    bool translate = true,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = scaffoldMessengerKey.currentState;
    final ctx = scaffoldMessengerKey.currentContext;
    if (messenger == null || ctx == null) return;
    final c = ctx.colors;
    final (icon, accent) = switch (variant) {
      CToastVariant.success => (LucideIcons.circleCheck, c.accent),
      CToastVariant.error => (LucideIcons.circleAlert, StatusColors.danger),
      CToastVariant.info => (LucideIcons.info, c.accent),
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: duration,
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: c.modalCard,
          margin: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, 16.ms),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.ms),
            side: BorderSide(color: c.modalBorder),
          ),
          content: Row(
            children: [
              Icon(icon, size: 18.ms, color: accent),
              SizedBox(width: 10.ms),
              Expanded(
                child: translate
                    ? CText(
                        message,
                        variables: variables,
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.modalText,
                      )
                    : CText.raw(
                        message,
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.modalText,
                      ),
              ),
            ],
          ),
        ),
      );
  }

  static void error(Object error) {
    final e = error is ApiException ? error : ApiException.from(error);
    if (e.type == ApiErrorType.cancelled || e.type == ApiErrorType.loggingOut) {
      return;
    }
    final ctx = scaffoldMessengerKey.currentContext;
    if (ctx == null) return;
    show(
      e.localizedMessage(ctx),
      variant: CToastVariant.error,
      translate: false,
    );
  }

  /// Translates outside a widget (rarely needed).
  static String tr(String key) =>
      scaffoldMessengerKey.currentContext?.t(key) ?? key;
}
