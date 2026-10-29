import 'package:flutter/material.dart';

import '../../core/analytics/events/auth_events.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../component/c_loader.dart';
import '../component/c_text.dart';
import '../component/exit_on_double_back.dart';
import '../component/pressable.dart';
import '../component/status_bar_style.dart';
import 'helper/onboarding_actions.dart';

/// Layout shared by the age gate and the language step: icon badge, title,
/// body, then [children]. Reached by a reset: back asks to press again, then
/// exits (RN).
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.children,
    this.titleRaw = false,
    this.bodyRaw = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  /// [title] / [body] come from the server, not i18n.
  final bool titleRaw;
  final bool bodyRaw;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = danger ? StatusColors.dangerRed : c.accent;
    final muted = c.isDark ? AppColors.whiteA(0.6) : AppColors.blackA(0.58);
    Widget text(
      String v, {
      required bool raw,
      required double size,
      required FontWeight w,
      required Color color,
      double? height,
    }) => raw
        ? CText.raw(v, size: size, weight: w, color: color, height: height)
        : CText(v, size: size, weight: w, color: color, height: height);

    return ExitOnDoubleBack(
      child: ThemedStatusBar(
        child: Scaffold(
          backgroundColor: c.isDark ? DarkColors.bg : AppColors.white,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 28.ms,
                      vertical: 24.ms,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 62.ms,
                          height: 62.ms,
                          margin: EdgeInsets.only(bottom: 18.ms),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 28.ms, color: accent),
                        ),
                        text(
                          title,
                          raw: titleRaw,
                          size: 24,
                          w: FontWeight.w900,
                          color: c.text,
                        ),
                        SizedBox(height: 10.ms),
                        text(
                          body,
                          raw: bodyRaw,
                          size: 13,
                          w: FontWeight.w500,
                          color: muted,
                          height: 20,
                        ),
                        SizedBox(height: 24.ms),
                        ...children,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Not you? Sign out" (the router guard then shows login).
class SignOutLink extends StatefulWidget {
  const SignOutLink({
    super.key,
    this.enabled = true,
    this.screen = 'onboarding',
  });
  final bool enabled;

  /// Analytics: the step it sits on (`age_gate`, `language`).
  final String screen;

  @override
  State<SignOutLink> createState() => _SignOutLinkState();
}

class _SignOutLinkState extends State<SignOutLink> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = c.isDark ? AppColors.whiteA(0.6) : AppColors.blackA(0.58);
    return Center(
      child: Pressable(
        onPressed: !widget.enabled || _busy
            ? null
            : () {
                setState(() => _busy = true);
                AuthEvents.onboardingSignOut(screen: widget.screen);
                OnboardingActions.signOut();
              },
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12.ms, horizontal: 16.ms),
          child: _busy
              ? CLoader(size: 18, color: muted)
              : Opacity(
                  opacity: widget.enabled ? 1 : 0.5, // RN: dimmed while busy
                  child: CText(
                    'auth:onboarding.sign_out',
                    size: 12,
                    weight: FontWeight.w800,
                    color: muted,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Muted centered note / error line.
class OnboardingNote extends StatelessWidget {
  const OnboardingNote(
    this.text, {
    super.key,
    this.error = false,
    this.variables,
    this.raw = false,
  });
  final String text;
  final bool error;
  final bool raw;
  final Map<String, dynamic>? variables;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = error
        ? StatusColors.dangerRed
        : (c.isDark ? AppColors.whiteA(0.6) : AppColors.blackA(0.58));
    return Padding(
      padding: EdgeInsets.only(top: 12.ms),
      child: raw
          ? CText.raw(text, size: 12, weight: FontWeight.w700, color: color)
          : CText(
              text,
              variables: variables,
              size: 12,
              weight: FontWeight.w700,
              color: color,
            ),
    );
  }
}
