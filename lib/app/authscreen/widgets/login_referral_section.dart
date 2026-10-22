import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_input.dart';
import '../helper/login_referral.dart';
import 'auth_theme.dart';
import 'login_parts.dart';

/// "Have a referral code?", then the code field with live validation. A
/// code applies to Google / Apple as well as OTP sign-in.
class LoginReferralSection extends StatelessWidget {
  const LoginReferralSection(this.referral, {super.key});
  final LoginReferral referral;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: referral.open,
      builder: (_, open, _) => open
          ? _ReferralField(referral)
          : AuthLink(
              icon: LucideIcons.ticket,
              label: 'auth:login.have_referral',
              textSize: 14.5,
              onPressed: referral.show,
            ),
    );
  }
}

class _ReferralField extends StatelessWidget {
  const _ReferralField(this.referral);
  final LoginReferral referral;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    Widget note(String text, Color color) => Padding(
      padding: EdgeInsets.only(top: 8.ms),
      child: Text(
        text,
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: AuthTheme.text(13, color: color, weight: FontWeight.w700),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: 18.ms),
      child: ListenableBuilder(
        listenable: Listenable.merge([referral.status, referral.referrerName]),
        builder: (_, _) {
          final status = referral.status.value;
          final name = referral.referrerName.value;
          return Column(
            children: [
              CInput(
                type: CInputType.referral,
                controller: referral.code,
                placeholder: 'auth:login.referral_placeholder',
                maxLength: 8,
                inputFormatters: [_UpperCase()],
                onChanged: referral.onChanged,
                bottomSpacing: 0,
                trailing: switch (status) {
                  ReferralStatus.checking => SizedBox.square(
                    dimension: 18,
                    child: RepaintBoundary(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.accent,
                      ),
                    ),
                  ),
                  ReferralStatus.valid => Icon(
                    LucideIcons.check,
                    size: 20.ms,
                    color: t.success,
                  ),
                  _ => null,
                },
              ),
              if (name != null)
                note(
                  context.t('auth:login.invited_by', variables: {'name': name}),
                  t.accent,
                ),
              if (status == ReferralStatus.invalid &&
                  referral.code.text.isNotEmpty)
                note(context.t('auth:login.referral_invalid'), t.danger),
            ],
          );
        },
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue _,
    TextEditingValue next,
  ) => next.copyWith(text: next.text.toUpperCase());
}
