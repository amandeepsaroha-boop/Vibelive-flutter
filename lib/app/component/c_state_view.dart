import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import 'c_button.dart';
import 'c_text.dart';

/// Full-area message: empty list, error with retry, offline.
class CStateView extends StatelessWidget {
  const CStateView({
    super.key,
    required this.title,
    this.message,
    this.icon = LucideIcons.inbox,
    this.actionLabel,
    this.onAction,
    this.translateMessage = true,
    this.actionVariant = CButtonVariant.outline,
  });

  /// Empty state with an optional action.
  const CStateView.empty({
    super.key,
    this.title = 'states.empty_title',
    this.message = 'states.empty_message',
    this.actionLabel,
    this.onAction,
    this.actionVariant = CButtonVariant.outline,
  }) : icon = LucideIcons.inbox,
       translateMessage = true;

  /// Error state for any exception, with "Retry".
  factory CStateView.error(
    BuildContext context,
    Object error, {
    Key? key,
    VoidCallback? onRetry,
  }) {
    final e = error is ApiException ? error : ApiException.from(error);
    final offline =
        e.type == ApiErrorType.network || e.type == ApiErrorType.timeout;
    return CStateView(
      key: key,
      title: offline ? 'states.offline_title' : 'errors.title',
      message: e.localizedMessage(context),
      translateMessage: false,
      icon: offline ? LucideIcons.wifiOff : LucideIcons.circleAlert,
      actionLabel: onRetry == null ? null : 'actions.retry',
      onAction: onRetry,
    );
  }

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool translateMessage;

  /// Style of the action button (RN screens differ: outline or filled).
  final CButtonVariant actionVariant;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.ms, vertical: 24.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56.ms,
              height: 56.ms,
              decoration: BoxDecoration(
                color: c.surfaceVariant,
                borderRadius: BorderRadius.circular(18.ms),
                border: Border.all(color: c.border),
              ),
              child: Icon(icon, size: 24.ms, color: c.textMuted),
            ),
            SizedBox(height: 14.ms),
            CText(
              title,
              size: 18,
              weight: FontWeight.w900,
              align: TextAlign.center,
            ),
            if (message != null) ...[
              SizedBox(height: 6.ms),
              translateMessage
                  ? CText(
                      message!,
                      size: 14,
                      weight: FontWeight.w600,
                      color: c.textMuted,
                      align: TextAlign.center,
                      height: 20,
                    )
                  : CText.raw(
                      message!,
                      size: 14,
                      weight: FontWeight.w600,
                      color: c.textMuted,
                      align: TextAlign.center,
                      height: 20,
                    ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: 18.ms),
              CButton(
                title: actionLabel!,
                variant: actionVariant,
                showArrow: false,
                width: 180.ms,
                height: 46.ms,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
