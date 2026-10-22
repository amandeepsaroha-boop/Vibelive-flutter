import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../component/c_button.dart';
import '../component/c_text.dart';
import '../component/pressable.dart';
import '../component/status_bar_style.dart';
import 'helper/auth_credentials.dart';

/// Terms & Conditions (RN `TermsAndConditions`): read-only from the login
/// link, or the one-time consent after Google / Apple sign-in, where it can
/// only be left with Agree or Cancel.
class TermsScreen extends StatefulWidget {
  const TermsScreen._({this.provider});

  /// Null = read-only.
  final String? provider;

  static Future<void> show(BuildContext context) =>
      _open(context, const TermsScreen._());

  /// True when the user agreed.
  static Future<bool> askConsent(BuildContext context, String provider) async =>
      await _open(context, TermsScreen._(provider: provider)) == true;

  static Future<bool?> _open(
    BuildContext context,
    TermsScreen page,
  ) => Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _agreed = false;
  late final _links = [
    for (final url in const [
      AuthCredentials.termsUrl,
      AuthCredentials.privacyUrl,
      AuthCredentials.guidelinesUrl,
    ])
      TapGestureRecognizer()..onTap = () => _open(url),
  ];

  bool get _readOnly => widget.provider == null;

  static void _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  void dispose() {
    for (final r in _links) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final insets = MediaQuery.paddingOf(context);
    final card = c.isDark ? AppColors.whiteA(0.04) : AppColors.white;
    final muted = c.isDark ? AppColors.whiteA(0.55) : AppColors.blackA(0.5);
    final provider = widget.provider?.toLowerCase();

    return PopScope(
      canPop: _readOnly,
      child: ThemedStatusBar(
        child: Scaffold(
          backgroundColor: c.bg,
          body: Padding(
            padding: EdgeInsets.fromLTRB(22.ms, insets.top + 20.ms, 22.ms, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56.ms,
                  height: 56.ms,
                  decoration: BoxDecoration(
                    color: c.accentA(0.14),
                    borderRadius: BorderRadius.circular(20.ms),
                    border: Border.all(color: c.accentA(0.3)),
                  ),
                  child: Icon(
                    LucideIcons.shieldCheck,
                    size: 26.ms,
                    color: c.accent,
                  ),
                ),
                SizedBox(height: 14.ms),
                CText(
                  'auth:terms.title',
                  size: 26,
                  weight: FontWeight.w900,
                  color: c.text,
                ),
                SizedBox(height: 6.ms),
                CText(
                  _readOnly
                      ? 'auth:terms.intro_read'
                      : provider == 'apple' || provider == 'google'
                      ? 'auth:terms.intro_provider'
                      : 'auth:terms.intro',
                  variables: provider == null
                      ? null
                      : {'provider': context.t('auth:login.$provider')},
                  size: 13,
                  height: 19,
                  color: muted,
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.only(top: 16.ms, bottom: 16.ms),
                    children: [
                      for (var i = 1; i <= 7; i++)
                        Container(
                          margin: EdgeInsets.only(bottom: 10.ms),
                          padding: EdgeInsets.all(14.ms),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(18.ms),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CText(
                                'auth:terms.s$i.title',
                                size: 13,
                                weight: FontWeight.w900,
                                color: c.text,
                              ),
                              SizedBox(height: 6.ms),
                              CText(
                                'auth:terms.s$i.body',
                                size: 12.5,
                                height: 19,
                                color: muted,
                              ),
                            ],
                          ),
                        ),
                      Wrap(
                        spacing: 8.ms,
                        runSpacing: 8.ms,
                        children: [
                          for (final (key, url) in const [
                            (
                              'auth:terms.terms_of_use',
                              AuthCredentials.termsUrl,
                            ),
                            ('auth:terms.privacy', AuthCredentials.privacyUrl),
                            (
                              'auth:terms.guidelines',
                              AuthCredentials.guidelinesUrl,
                            ),
                          ])
                            Pressable(
                              onPressed: () => _open(url),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12.ms,
                                  vertical: 8.ms,
                                ),
                                decoration: BoxDecoration(
                                  color: card,
                                  borderRadius: BorderRadius.circular(12.ms),
                                  border: Border.all(color: c.border),
                                ),
                                child: CText(
                                  key,
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: c.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_readOnly)
                  CButton(
                    title: 'auth:terms.close',
                    showArrow: false,
                    height: 56.ms,
                    onPressed: () => Navigator.of(context).pop(),
                  )
                else ...[
                  _agreeRow(c, card, muted),
                  SizedBox(height: 12.ms),
                  CButton(
                    title: 'auth:terms.agree',
                    showArrow: false,
                    height: 56.ms,
                    disabled: !_agreed,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  Pressable(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: SizedBox(
                      height: 46.ms,
                      width: double.infinity,
                      child: Center(
                        child: CText(
                          'auth:terms.cancel',
                          size: 12,
                          weight: FontWeight.w700,
                          color: muted,
                        ),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: math.max(insets.bottom, 12.ms)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _agreeRow(VibeColors c, Color card, Color muted) {
    final base = TextStyle(fontSize: 12.5.ms, height: 18 / 12.5, color: c.text);
    final link = base.copyWith(
      color: c.accent,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: c.accent,
    );
    return Pressable(
      activeOpacity: 0.85,
      onPressed: () => setState(() => _agreed = !_agreed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(14.ms),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(18.ms),
          border: Border.all(color: _agreed ? c.accent : c.border),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24.ms,
              height: 24.ms,
              decoration: BoxDecoration(
                color: _agreed ? c.accent : AppColors.transparent,
                borderRadius: BorderRadius.circular(8.ms),
                border: Border.all(
                  width: 2,
                  color: _agreed ? c.accent : c.border,
                ),
              ),
              child: _agreed
                  ? Icon(Icons.check_rounded, size: 15.ms, color: c.onAccent)
                  : null,
            ),
            SizedBox(width: 12.ms),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    TextSpan(text: '${context.t('auth:terms.agree_prefix')} '),
                    TextSpan(
                      text: context.t('auth:terms.terms_of_use'),
                      style: link,
                      recognizer: _links[0],
                    ),
                    const TextSpan(text: ', '),
                    TextSpan(
                      text: context.t('auth:terms.privacy'),
                      style: link,
                      recognizer: _links[1],
                    ),
                    TextSpan(text: context.t('auth:terms.and_joiner')),
                    TextSpan(
                      text: context.t('auth:terms.guidelines'),
                      style: link,
                      recognizer: _links[2],
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
