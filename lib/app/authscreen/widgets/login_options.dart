import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/authscreen/auth_models.dart';
import '../helper/auth_credentials.dart';
import '../helper/login_controller.dart';
import '../terms_screen.dart';
import 'auth_decorations.dart';
import 'auth_option_button.dart';
import 'auth_theme.dart';
import 'login_parts.dart';
import 'login_referral_section.dart';

/// The sign-in options page (RN `renderSignInOptions`): headline, Google
/// (then Apple on iOS), OR, mobile number, "Use email instead", the legal
/// line and the referral code. Each part listens only to what it shows.
class LoginOptions extends StatelessWidget {
  const LoginOptions(this.c, {super.key});
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Hero(c),
        SizedBox(height: 30.ms),
        _SocialButtons(c),
        ValueListenableBuilder<UiText?>(
          valueListenable: c.error,
          builder: (_, error, _) =>
              error == null ? const SizedBox.shrink() : LoginErrorText(error),
        ),
        const _OrRow(),
        ValueListenableBuilder<bool>(
          valueListenable: c.busy,
          builder: (_, busy, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthOptionButton(
                tinted: true,
                icon: Icon(
                  LucideIcons.smartphone,
                  size: 26.ms,
                  color: t.accent,
                ),
                label: 'auth:login.mobile',
                disabled: busy,
                onPressed: () => c.openMethod(OtpChannel.sms),
              ),
              AuthLink(
                icon: LucideIcons.mail,
                iconSize: 22,
                label: 'auth:login.use_email',
                onPressed: busy ? null : () => c.openMethod(OtpChannel.email),
              ),
            ],
          ),
        ),
        const _Legal(),
        Center(
          child: Container(
            width: 70.ms,
            height: 1,
            margin: EdgeInsets.only(top: 18.ms),
            color: t.line,
          ),
        ),
        LoginReferralSection(c.referral),
        Padding(
          padding: EdgeInsets.only(top: 2.ms),
          child: Align(
            alignment: Alignment.centerRight,
            // RN `marginRight: -8`: hangs into the page margin.
            child: Transform.translate(
              offset: Offset(8.ms, 0),
              child: Squiggle(color: t.lime, width: 76.ms, weight: 8),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Good / conversations / live here." with the spark, tagline, invite.
class _Hero extends StatelessWidget {
  const _Hero(this.c);
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: double.infinity,
              // A long word ("conversations") shrinks on a narrow phone
              // instead of breaking mid-word.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Semantics(
                  header: true,
                  child: AuthText.rich(
                    TextSpan(
                      style: AuthTheme.text(
                        40,
                        color: t.ink,
                        weight: FontWeight.w800,
                        height: 44,
                        spacing: -1.4,
                      ),
                      children: [
                        TextSpan(
                          text: '${context.t('auth:login.headline.lead')}\n',
                        ),
                        TextSpan(
                          text: '${context.t('auth:login.headline.accent')}\n',
                          style: TextStyle(color: t.accent),
                        ),
                        TextSpan(text: context.t('auth:login.headline.tail')),
                        TextSpan(
                          text: context.t('auth:login.headline.dot'),
                          style: TextStyle(color: t.lime),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2.ms,
              right: -2.ms,
              child: Spark(color: t.lime),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(top: 14.ms),
          child: Text(
            context.t('auth:login.tagline'),
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            style: AuthTheme.text(17, color: t.muted, height: 24),
          ),
        ),
        ValueListenableBuilder<String?>(
          valueListenable: c.referral.referrerName,
          builder: (_, name, _) => name == null
              ? const SizedBox.shrink()
              : Container(
                  margin: EdgeInsets.only(top: 14.ms),
                  padding: EdgeInsets.symmetric(
                    vertical: 6.ms,
                    horizontal: 14.ms,
                  ),
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.t(
                      'auth:login.invited_by',
                      variables: {'name': name},
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaler.noScaling,
                    style: AuthTheme.text(
                      13,
                      color: t.accent,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Google first: the one-tap path. Apple under it on iOS only (required
/// wherever another third-party login is offered).
class _SocialButtons extends StatelessWidget {
  const _SocialButtons(this.c);
  final LoginController c;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([c.busy, c.socialBusy, c.appleAvailable]),
      builder: (_, _) {
        final active = c.socialBusy.value;
        Widget button(SocialProvider p, Widget icon, String label) =>
            AuthOptionButton(
              icon: icon,
              label: label,
              loading: active == p,
              disabled: c.busy.value || (active != null && active != p),
              onPressed: () => c.social(p),
            );
        final logo = 30.ms;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            button(
              SocialProvider.google,
              // The PNG carries its own padding around the "G".
              Image.asset(
                AppImages.googleLogo,
                width: logo,
                height: logo,
                cacheWidth: (logo * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              ),
              'auth:login.google',
            ),
            if (c.appleAvailable.value) ...[
              SizedBox(height: 14.ms),
              button(
                SocialProvider.apple,
                // Optical nudge: the glyph's box sits low.
                Transform.translate(
                  offset: Offset(0, -2.ms),
                  child: Icon(Icons.apple, size: 24.ms, color: t.ink),
                ),
                'auth:login.apple',
              ),
            ],
          ],
        );
      },
    );
  }
}

/// ───── OR ─────
class _OrRow extends StatelessWidget {
  const _OrRow();

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    final line = Expanded(child: Container(height: 1, color: t.line));
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.ms, horizontal: 10.ms),
      child: Row(
        children: [
          line,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.ms),
            child: Text(
              context.t('auth:login.or'),
              textScaler: TextScaler.noScaling,
              style: AuthTheme.text(
                13,
                color: t.faint,
                weight: FontWeight.w600,
                spacing: 0.5,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// "By continuing, you agree to our Terms & Conditions and Privacy Policy."
/// Read-only: the sheet's checkbox is still what gates SEND OTP.
class _Legal extends StatelessWidget {
  const _Legal();

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    final suffix = context.t('auth:login.legal.suffix');
    return Padding(
      padding: EdgeInsets.only(top: 26.ms),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: double.infinity,
            child: LinkedText(
              style: AuthTheme.text(13.5, color: t.muted, height: 21),
              linkColor: t.accent,
              parts: [
                TextPart('${context.t('auth:login.legal.prefix')}\n'),
                TextPart(
                  context.t('auth:login.terms_link'),
                  onTap: () => TermsScreen.show(context),
                ),
                TextPart(context.t('auth:login.legal.and')),
                TextPart(
                  context.t('auth:login.legal.privacy'),
                  onTap: () => launchUrl(
                    Uri.parse(AuthCredentials.privacyUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                if (suffix.isNotEmpty) TextPart(suffix),
              ],
            ),
          ),
          Positioned(
            left: -6.ms,
            top: -4.ms,
            child: Squiggle(color: t.accent),
          ),
        ],
      ),
    );
  }
}
