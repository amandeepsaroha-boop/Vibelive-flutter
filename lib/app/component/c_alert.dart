import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/analytics/events/me_events.dart';
import '../../core/analytics/screen_tracker.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/log.dart';
import '../../core/utils/scale.dart';
import 'c_button.dart';
import 'c_text.dart';

/// RN `VibeAlertModal` variants.
enum CAlertVariant { success, error, warning, info }

/// App alert dialog (RN `VibeAlertModal`). Works without a context (uses the
/// root navigator), and the same alert is never stacked twice.
///
/// Returns `true` for the primary button, `false` for the secondary one and
/// `null` when dismissed.
///
/// ```dart
/// await CAlert.show(title: 'payment:success_title', variant: CAlertVariant.success);
/// final ok = await CAlert.confirm(title: 'client:block_title', message: 'client:block_msg');
/// CAlert.error(e); // ApiException or anything else
/// ```
abstract final class CAlert {
  static final Set<String> _open = {};

  static Future<bool?> show({
    BuildContext? context,
    String? title,
    String? message,
    Map<String, dynamic>? variables,
    CAlertVariant variant = CAlertVariant.info,
    String primaryLabel = 'actions.ok',
    String? secondaryLabel,

    /// false = [title]/[message] are literal text (e.g. server messages).
    bool translate = true,
    bool dismissible = true,

    /// Analytics screen name; defaults to one derived from the title key.
    String? analyticsName,
  }) async {
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      Log.w('CAlert', 'no navigator for "$title"');
      return null;
    }
    final id = '$variant|$title|$message';
    if (!_open.add(id)) return null;
    final name = analyticsName ?? nameFor(title, translate: translate);
    try {
      final result = await showGeneralDialog<bool>(
        context: ctx,
        useRootNavigator: true,
        routeSettings: ScreenTracker.sheet(name),
        barrierDismissible: dismissible,
        barrierLabel: 'alert',
        barrierColor: ctx.colors.modalBackdrop,
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        pageBuilder: (dialogContext, _, _) => PopScope(
          canPop: dismissible,
          child: _AlertCard(
            title: title,
            message: message,
            variables: variables,
            variant: variant,
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel,
            translate: translate,
          ),
        ),
      );
      UiEvents.dialogAction(
        dialog: name,
        action: switch (result) {
          true => 'primary',
          false => 'secondary',
          null => 'dismissed',
        },
      );
      return result;
    } finally {
      _open.remove(id);
    }
  }

  /// Analytics name of an alert: `alert_<title key>` (`alert_resources_
  /// logout_title`), or `alert` for literal text.
  @visibleForTesting
  static String nameFor(String? title, {bool translate = true}) {
    if (!translate || title == null || title.isEmpty) return 'alert';
    final slug = title
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .toLowerCase();
    if (slug.isEmpty) return 'alert';
    final name = 'alert_$slug';
    return name.length > 90 ? name.substring(0, 90) : name;
  }

  /// Primary + Cancel. Resolves to `true` only when confirmed.
  static Future<bool> confirm({
    BuildContext? context,
    required String title,
    String? message,
    Map<String, dynamic>? variables,
    String confirmLabel = 'actions.confirm',
    String cancelLabel = 'actions.cancel',
    CAlertVariant variant = CAlertVariant.warning,
    String? analyticsName,
  }) async =>
      await show(
        context: context,
        title: title,
        message: message,
        variables: variables,
        variant: variant,
        primaryLabel: confirmLabel,
        secondaryLabel: cancelLabel,
        analyticsName: analyticsName,
      ) ==
      true;

  /// Shows any error. [ApiException] gets its own copy (server message when
  /// readable, otherwise the translated text for its type).
  static Future<void> error(
    Object error, {
    BuildContext? context,
    String title = 'errors.title',
  }) async {
    final e = error is ApiException ? error : ApiException.from(error);
    if (e.type == ApiErrorType.cancelled || e.type == ApiErrorType.loggingOut) {
      return;
    }
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    UiEvents.errorAlert(e);
    await show(
      context: ctx,
      title: ctx.t(title),
      message: e.localizedMessage(ctx),
      variant: CAlertVariant.error,
      translate: false,
      analyticsName: 'error_alert',
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.title,
    required this.message,
    required this.variables,
    required this.variant,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.translate,
  });

  final String? title;
  final String? message;
  final Map<String, dynamic>? variables;
  final CAlertVariant variant;
  final String primaryLabel;
  final String? secondaryLabel;
  final bool translate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, accent, bg, border) = switch (variant) {
      CAlertVariant.success => (
        LucideIcons.badgeCheck,
        c.accent,
        c.accentA(0.14),
        c.accentA(0.3),
      ),
      CAlertVariant.error => (
        LucideIcons.circleAlert,
        StatusColors.danger,
        StatusColors.dangerA(0.14),
        StatusColors.dangerA(0.28),
      ),
      CAlertVariant.warning => (
        LucideIcons.triangleAlert,
        StatusColors.warning,
        StatusColors.warningA(0.16),
        StatusColors.warningA(0.28),
      ),
      CAlertVariant.info => (
        LucideIcons.info,
        c.accent,
        c.accentA(0.12),
        c.accentA(0.28),
      ),
    };

    Widget text(
      String value, {
      required double size,
      required FontWeight w,
      required Color color,
      double? height,
    }) => translate
        ? CText(
            value,
            variables: variables,
            size: size,
            weight: w,
            color: color,
            height: height,
          )
        : CText.raw(value, size: size, weight: w, color: color, height: height);

    return _AboveKeyboard(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 22.ms),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: EdgeInsets.fromLTRB(18.ms, 18.ms, 18.ms, 16.ms),
                decoration: BoxDecoration(
                  color: c.modalCard,
                  borderRadius: BorderRadius.circular(24.ms),
                  border: Border.all(color: c.modalBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54.ms,
                      height: 54.ms,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(18.ms),
                        border: Border.all(color: border),
                      ),
                      child: Icon(icon, size: 24.ms, color: accent),
                    ),
                    SizedBox(height: 14.ms),
                    if (title != null && title!.isNotEmpty)
                      text(
                        title!,
                        size: 20,
                        w: FontWeight.w900,
                        color: c.modalText,
                      )
                    else
                      CText(
                        'alert.notice',
                        size: 20,
                        weight: FontWeight.w900,
                        color: c.modalText,
                      ),
                    if (message != null && message!.isNotEmpty) ...[
                      SizedBox(height: 8.ms),
                      // A long server message scrolls; the buttons stay.
                      Flexible(
                        child: SingleChildScrollView(
                          child: text(
                            message!,
                            size: 14,
                            w: FontWeight.w700,
                            color: c.modalMuted,
                            height: 20,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 18.ms),
                    Row(
                      children: [
                        if (secondaryLabel != null) ...[
                          Expanded(
                            child: CButton(
                              title: secondaryLabel!,
                              variant: CButtonVariant.outline,
                              showArrow: false,
                              height: 46.ms,
                              onPressed: () => Navigator.of(context).pop(false),
                            ),
                          ),
                          SizedBox(width: 10.ms),
                        ],
                        Expanded(
                          child: CButton(
                            title: primaryLabel,
                            showArrow: false,
                            height: 46.ms,
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lifts the alert above an open keyboard (e.g. a rejected OTP while the
/// code field has focus). Only this wrapper rebuilds per keyboard frame.
class _AboveKeyboard extends StatelessWidget {
  const _AboveKeyboard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 100),
    curve: Curves.decelerate,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}
