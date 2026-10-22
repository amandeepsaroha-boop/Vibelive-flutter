import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/authscreen/auth_models.dart';
import '../../component/c_input.dart';
import '../../component/pressable.dart';
import '../helper/login_controller.dart';
import '../helper/sms_otp_autofill.dart';
import '../terms_screen.dart';
import 'auth_primary_button.dart';
import 'auth_theme.dart';
import 'login_parts.dart';

/// Email or mobile entry in the sheet (RN `renderIdentifierForm`): field,
/// terms checkbox, SEND OTP and the switch to the other method.
class LoginFormStep extends StatelessWidget {
  const LoginFormStep(
    this.c, {
    super.key,
    required this.email,
    required this.phoneRequired,
    this.focusDelay = Duration.zero,
  });

  final LoginController c;
  final bool email;

  /// The backend asked a social user for a number: no switching away.
  final bool phoneRequired;

  /// The field takes focus (keyboard up) after this: the sheet's slide-in
  /// when the sheet opens with this step, none when switching inside it.
  final Duration focusDelay;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    final title = email
        ? 'enter_email'
        : (phoneRequired ? 'verify_mobile' : 'enter_mobile');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthStepTitle(
          lead: 'auth:login.form_title.$title.lead',
          accent: 'auth:login.form_title.$title.accent',
        ),
        AuthStepSubtitle(
          child: Text(
            context.t(
              phoneRequired
                  ? 'auth:login.subtitle.phone_required'
                  : email
                  ? 'auth:login.subtitle.email'
                  : 'auth:login.subtitle.sms',
              variables: {'digits': otpLength},
            ),
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: AuthTheme.text(15.5, color: t.muted, height: 22),
          ),
        ),
        ValueListenableBuilder<UiText?>(
          valueListenable: c.error,
          builder: (_, error, _) => CInput(
            key: ValueKey(email),
            type: email ? CInputType.email : CInputType.mobile,
            controller: email ? c.email : c.phone,
            placeholder: email
                ? 'auth:login.email_placeholder'
                : 'auth:login.phone_placeholder',
            maxLength: email ? null : 10,
            autofocus: true,
            autofocusDelay: focusDelay,
            errorText: error?.value,
            translateError: !(error?.raw ?? false),
            textInputAction: email
                ? TextInputAction.send
                : TextInputAction.done,
            onChanged: (_) => c.clearError(),
            onSubmitted: (_) => c.sendOtp(),
            onFocus: email ? null : c.offerPhoneHint,
            bottomSpacing: 0,
          ),
        ),
        _TermsRow(c),
        ValueListenableBuilder<bool>(
          valueListenable: c.busy,
          builder: (_, busy, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 18.ms),
              // Stays tappable without the tick: tapping points at the box.
              AuthPrimaryButton(
                title: 'auth:login.send_otp',
                loading: busy,
                onPressed: c.sendOtp,
              ),
              if (!phoneRequired)
                AuthLink(
                  icon: email ? LucideIcons.smartphone : LucideIcons.mail,
                  label: email
                      ? 'auth:login.use_mobile'
                      : 'auth:login.use_email',
                  onPressed: busy
                      ? null
                      : () => c.openMethod(
                          email ? OtpChannel.sms : OtpChannel.email,
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Checkbox + "I agree to the Terms & Conditions". The link opens the page
/// read-only and does not tick the box; SEND OTP unticked turns it red.
class _TermsRow extends StatelessWidget {
  const _TermsRow(this.c);
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    final suffix = context.t('auth:login.agree.suffix');
    return ListenableBuilder(
      listenable: Listenable.merge([c.termsAccepted, c.termsNudge]),
      builder: (_, _) {
        final on = c.termsAccepted.value;
        final nudge = c.termsNudge.value;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 18.ms, bottom: 4.ms),
              child: Semantics(
                checked: on,
                child: Pressable(
                  key: const ValueKey('login-terms'),
                  onPressed: c.toggleTerms,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.ms),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 22.ms,
                          height: 22.ms,
                          decoration: BoxDecoration(
                            color: on ? t.primary : t.card,
                            borderRadius: BorderRadius.circular(7.ms),
                            border: Border.all(
                              width: 1.5,
                              color: on
                                  ? t.primary
                                  : (nudge ? t.danger : t.line),
                            ),
                          ),
                          child: on
                              ? Icon(
                                  LucideIcons.check,
                                  size: 14.ms,
                                  color: t.primaryText,
                                )
                              : null,
                        ),
                        SizedBox(width: 10.ms),
                        Flexible(
                          child: LinkedText(
                            style: AuthTheme.text(14, color: t.muted),
                            linkColor: t.accent,
                            parts: [
                              TextPart(context.t('auth:login.agree.prefix')),
                              TextPart(
                                context.t('auth:login.terms_link'),
                                onTap: () => TermsScreen.show(context),
                              ),
                              if (suffix.isNotEmpty) TextPart(suffix),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (nudge)
              Padding(
                padding: EdgeInsets.only(top: 2.ms),
                child: Text(
                  context.t('auth:login.errors.accept_terms'),
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: AuthTheme.text(
                    12.5,
                    color: t.danger,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
