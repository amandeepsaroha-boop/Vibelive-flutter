import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/scale.dart';
import '../api/authscreen/auth_models.dart';
import '../component/app_logo.dart';
import '../component/c_input.dart';
import '../component/exit_on_double_back.dart';
import 'helper/login_controller.dart';
import 'terms_screen.dart';
import 'widgets/auth_sheet.dart';
import 'widgets/auth_theme.dart';
import 'widgets/login_form_step.dart';
import 'widgets/login_options.dart';
import 'widgets/login_otp_step.dart';

/// Sign-in (RN `LoginScreen`): the options page (Google / Apple, mobile,
/// email), and the email / mobile form then the code in a bottom sheet over
/// it. Follows the app theme. All logic lives in [LoginController].
///
/// Performance: the entrance animations move cached layers (their content
/// is painted once), the sheet's field takes focus only once the sheet has
/// slid in, and nothing above the sheet listens to the keyboard.
class LoginScreen extends HookWidget {
  const LoginScreen({super.key, this.params = const {}});

  /// Route query (`referral` / `code` from a link).
  final Map<String, String> params;

  /// Wordmark width; the splash decodes the logo at this size ahead.
  static double get logoWidth => 196.ms;

  /// After the entrance animations: warm what the sheet's first frame
  /// would otherwise pay for (the emoji font of the mobile field's flag).
  static const _warmUpAfter = Duration(milliseconds: 700);

  @override
  Widget build(BuildContext context) {
    final c = useMemoized(
      () => LoginController(
        routeParams: params,
        navigate: (route) {
          if (context.mounted) context.go(route);
        },
        askConsent: (provider) => TermsScreen.askConsent(context, provider),
      ),
    );
    useEffect(() => c.dispose, [c]);
    useEffect(() => Timer(_warmUpAfter, CInput.warmUp).cancel, const []);
    final t = AuthTheme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: AppColors.transparent,
            systemNavigationBarColor: t.bg,
          ),
      // Inside the sheet Back steps back (code → form → closed); on the
      // options page a second press exits (RN).
      child: ExitOnDoubleBack(
        onBack: c.handleBack,
        child: Scaffold(
          backgroundColor: t.bg,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.symmetric(horizontal: 24.ms),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Logo(),
                      _FadeRise(child: LoginOptions(c)),
                      const _BottomGap(),
                    ],
                  ),
                ),
              ),
              Positioned.fill(child: _Sheet(c)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wordmark, fading and scaling in (RN header `MotiView`).
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final width = LoginScreen.logoWidth;
    return Padding(
      padding: EdgeInsets.only(top: 44.ms, bottom: 36.ms),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (_, v, logo) => Opacity(
          opacity: v,
          child: Transform.scale(scale: 0.94 + 0.06 * v, child: logo),
        ),
        // Painted once; each frame only scales and fades the layer.
        child: RepaintBoundary(
          child: Center(
            child: AppLogo(size: width, height: width * AppLogo.aspect),
          ),
        ),
      ),
    );
  }
}

/// Fades in and rises 12, 80 ms after the logo (RN options `MotiView`).
class _FadeRise extends StatelessWidget {
  const _FadeRise({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 400),
    curve: const Interval(0.2, 1, curve: Curves.easeInOut),
    builder: (_, v, options) => Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, 12.ms * (1 - v)),
        child: options,
      ),
    ),
    // The whole options page: painted once, not on each of these frames.
    child: RepaintBoundary(child: child),
  );
}

/// Home-indicator room under the options. Its own widget: the inset changes
/// while the keyboard moves and nothing else should rebuild for it.
class _BottomGap extends StatelessWidget {
  const _BottomGap();

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: MediaQuery.paddingOf(context).bottom + 12.ms);
}

/// The email / mobile sheet: form, then the code.
class _Sheet extends StatefulWidget {
  const _Sheet(this.c);
  final LoginController c;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  /// The sheet was up at the last build.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListenableBuilder(
      listenable: Listenable.merge([c.method, c.otpSent, c.phoneRequired]),
      builder: (context, _) {
        final method = c.method.value;
        final sent = c.otpSent.value;
        final required = c.phoneRequired.value;
        // Opening: the field waits for the slide-in before raising the
        // keyboard. Switching email / mobile inside the sheet: at once.
        final focusDelay = _open ? Duration.zero : AuthSheet.duration;
        _open = method != null;
        return AuthSheet(
          visible: method != null,
          onClose: required ? null : c.closeSheet,
          headerLeft: sent
              ? AuthSheetIconButton(
                  icon: LucideIcons.chevronLeft,
                  label: context.t('actions.back'),
                  onPressed: c.editIdentifier,
                )
              : null,
          child: method == null
              ? const SizedBox.shrink()
              : _StepIn(
                  key: ValueKey(sent ? 'otp' : method.name),
                  child: sent
                      ? LoginOtpStep(c)
                      : LoginFormStep(
                          c,
                          email: method == OtpChannel.email,
                          phoneRequired: required,
                          focusDelay: focusDelay,
                        ),
                ),
        );
      },
    );
  }
}

/// Each step fades in and rises 8 (RN keyed `MotiView`).
class _StepIn extends StatelessWidget {
  const _StepIn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeInOut,
    builder: (_, v, step) => Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, 8.ms * (1 - v)),
        child: step,
      ),
    ),
    child: RepaintBoundary(child: child),
  );
}
