import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../helper/login_controller.dart';
import '../helper/sms_otp_autofill.dart';
import 'auth_primary_button.dart';
import 'auth_theme.dart';
import 'login_parts.dart';

/// The code step in the sheet (RN `renderOtpStep`): four boxes over one
/// hidden field (iOS offers the SMS code on the keyboard; Android reads it
/// through [SmsOtpAutofill]), Verify and the resend countdown.
class LoginOtpStep extends StatelessWidget {
  const LoginOtpStep(this.c, {super.key});
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    const digits = {'digits': otpLength};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthStepTitle(
          lead: 'auth:login.code_title.lead',
          accent: 'auth:login.code_title.accent',
          variables: digits,
        ),
        AuthStepSubtitle(
          child: LinkedText(
            style: AuthTheme.text(15.5, color: t.muted, height: 22),
            linkColor: t.accent,
            parts: [
              TextPart(
                '${context.t('auth:login.sent_to', variables: {'target': c.sentTo})}  ',
              ),
              TextPart(context.t('auth:login.change'), onTap: c.editIdentifier),
            ],
          ),
        ),
        _OtpBoxes(c),
        ListenableBuilder(
          listenable: Listenable.merge([c.error, c.otpAutoFilled]),
          builder: (_, _) {
            final error = c.error.value;
            if (error != null) return LoginErrorText(error);
            if (!c.otpAutoFilled.value) return const SizedBox.shrink();
            return LoginErrorText(
              const UiText('auth:login.auto_filled'),
              color: t.success,
              weight: FontWeight.w700,
            );
          },
        ),
        SizedBox(height: 18.ms),
        ValueListenableBuilder<bool>(
          valueListenable: c.busy,
          builder: (_, busy, _) => AuthPrimaryButton(
            title: 'auth:login.verify',
            loading: busy,
            onPressed: c.verifyOtp,
          ),
        ),
        _ResendRow(c),
      ],
    );
  }
}

class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes(this.c);
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Center(
      child: Semantics(
        label: context.t(
          'auth:login.code_label',
          variables: {'digits': otpLength},
        ),
        child: GestureDetector(
          onTap: c.otpFocus.requestFocus,
          child: Stack(
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([c.otp, c.otpAutoFilled]),
                builder: (_, _) {
                  final code = c.otp.text;
                  final filled = c.otpAutoFilled.value;
                  final active = code.length.clamp(0, otpLength - 1);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < otpLength; i++)
                        _Slot(
                          digit: i < code.length ? code[i] : '',
                          border: filled
                              ? t.success
                              : (i == active ? t.accent : t.cardBorder),
                          fill: filled
                              ? t.successSoft
                              : (i == active ? t.accentSoft : t.card),
                          gap: i == 0 ? 0 : 14.ms,
                          ink: t.ink,
                        ),
                    ],
                  );
                },
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: c.otp,
                    focusNode: c.otpFocus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: otpLength,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    // iOS: the keyboard offers the code from the SMS.
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: c.onOtpChanged,
                    decoration: const InputDecoration(
                      // No label to float: no relayout animation on focus.
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.digit,
    required this.border,
    required this.fill,
    required this.gap,
    required this.ink,
  });

  final String digit;
  final Color border, fill, ink;
  final double gap;

  @override
  Widget build(BuildContext context) => Container(
    width: 60.ms,
    height: 66.ms,
    margin: EdgeInsets.only(left: gap),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(18.ms),
      border: Border.all(width: 1.5, color: border),
    ),
    child: Text(
      digit,
      textScaler: TextScaler.noScaling,
      style: AuthTheme.text(26, color: ink, weight: FontWeight.w800),
    ),
  );
}

/// Spinner while resending, "Didn't get it? Resend in 27s", then the link.
class _ResendRow extends StatelessWidget {
  const _ResendRow(this.c);
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 18.ms),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 30.ms),
        child: Center(
          child: ListenableBuilder(
            listenable: Listenable.merge([c.resending, c.resendIn, c.busy]),
            builder: (_, _) {
              if (c.resending.value) {
                return SizedBox.square(
                  dimension: 20,
                  child: RepaintBoundary(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: t.accent,
                    ),
                  ),
                );
              }
              final wait = c.resendIn.value;
              if (wait > 0) {
                return Text(
                  context.t(
                    'auth:login.resend_in',
                    variables: {'seconds': wait},
                  ),
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: AuthTheme.text(
                    14.5,
                    color: t.muted,
                    weight: FontWeight.w600,
                  ),
                );
              }
              return AuthLink(
                icon: LucideIcons.refreshCcw,
                iconSize: 16,
                gap: 8,
                top: 0,
                padding: EdgeInsets.symmetric(vertical: 6.ms),
                label: 'auth:login.resend',
                onPressed: c.busy.value ? null : c.resend,
              );
            },
          ),
        ),
      ),
    );
  }
}
