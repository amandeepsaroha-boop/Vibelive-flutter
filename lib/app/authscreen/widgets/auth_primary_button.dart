import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/pressable.dart';
import 'auth_theme.dart';

/// Solid brand-purple pill for the sign-in flow's main action (Send OTP /
/// Verify), RN `AuthPrimaryButton`. [title] is an i18n key.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.loading = false,
    this.disabled = false,
  });

  final String title;
  final VoidCallback onPressed;
  final bool loading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    final inactive = disabled || loading;
    final label = context.t(title);
    return Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: Semantics(
        label: label,
        enabled: !inactive,
        child: Pressable(
          onPressed: inactive ? null : onPressed,
          activeOpacity: 0.85,
          child: Container(
            height: 58.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.primary,
              borderRadius: BorderRadius.circular(29.ms),
              boxShadow: [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.28),
                  blurRadius: 14.ms,
                  offset: Offset(0, 6.ms),
                ),
              ],
            ),
            child: loading
                ? SizedBox.square(
                    dimension: 20,
                    child: RepaintBoundary(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: t.primaryText,
                      ),
                    ),
                  )
                : ExcludeSemantics(
                    child: Text(
                      label,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: AuthTheme.text(
                        17,
                        color: t.primaryText,
                        weight: FontWeight.w800,
                        spacing: 0.2,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
