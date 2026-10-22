import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/pressable.dart';
import '../helper/login_controller.dart';
import 'auth_theme.dart';

// Small pieces shared by the options page and the sheet steps.

/// Two-line step heading, the second line in the accent color ("Enter your
/// / mobile number"). [lead] and [accent] are i18n keys.
class AuthStepTitle extends StatelessWidget {
  const AuthStepTitle({
    super.key,
    required this.lead,
    required this.accent,
    this.variables,
  });

  final String lead;
  final String accent;
  final Map<String, dynamic>? variables;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Semantics(
      header: true,
      child: AuthText.rich(
        TextSpan(
          style: AuthTheme.text(
            30,
            color: t.ink,
            weight: FontWeight.w800,
            height: 35,
            spacing: -1,
          ),
          children: [
            TextSpan(text: '${context.t(lead, variables: variables)}\n'),
            TextSpan(
              text: context.t(accent, variables: variables),
              style: TextStyle(color: t.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muted line under a step title.
class AuthStepSubtitle extends StatelessWidget {
  const AuthStepSubtitle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 10.ms, bottom: 26.ms),
    child: child,
  );
}

/// Accent icon + bold label, centred (RN `linkRow`). [label] is an i18n key.
class AuthLink extends StatelessWidget {
  const AuthLink({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconSize = 20,
    this.textSize = 16,
    this.gap = 10,
    this.padding,
    this.top = 18,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double iconSize;
  final double textSize;
  final double gap;
  final EdgeInsets? padding;

  /// Unscaled space above.
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top.ms),
      child: Center(
        child: Pressable(
          onPressed: onPressed,
          child: Padding(
            padding:
                padding ??
                EdgeInsets.symmetric(vertical: 6.ms, horizontal: 10.ms),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize.ms, color: t.accent),
                SizedBox(width: gap.ms),
                Flexible(
                  child: Text(
                    context.t(label),
                    textScaler: TextScaler.noScaling,
                    style: AuthTheme.text(
                      textSize,
                      color: t.accent,
                      weight: FontWeight.w700,
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

/// Red line for a failure: an i18n key, or the server's own sentence.
class LoginErrorText extends StatelessWidget {
  const LoginErrorText(this.text, {super.key, this.color, this.weight});

  final UiText text;
  final Color? color;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 14.ms),
      child: Text(
        text.raw ? text.value : context.t(text.value),
        textAlign: TextAlign.center,
        textScaler: TextScaler.noScaling,
        style: AuthTheme.text(
          13,
          color: color ?? t.danger,
          weight: weight ?? FontWeight.w600,
        ),
      ),
    );
  }
}

/// One piece of [LinkedText]: plain, or an underlined accent link.
class TextPart {
  const TextPart(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;
}

/// A sentence with tappable links (RN nested `<Text onPress>`). Owns its
/// gesture recognizers. A link takes the touch: tapping it never also
/// triggers a parent's tap.
class LinkedText extends StatefulWidget {
  const LinkedText({
    super.key,
    required this.parts,
    required this.style,
    required this.linkColor,
    this.align = TextAlign.center,
  });

  final List<TextPart> parts;
  final TextStyle style;
  final Color linkColor;
  final TextAlign align;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

class _LinkedTextState extends State<LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizer(int i, VoidCallback onTap) {
    while (_recognizers.length <= i) {
      _recognizers.add(TapGestureRecognizer());
    }
    return _recognizers[i]..onTap = onTap;
  }

  @override
  Widget build(BuildContext context) {
    final link = TextStyle(
      color: widget.linkColor,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    var links = 0;
    return AuthText.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final part in widget.parts)
            part.onTap == null
                ? TextSpan(text: part.text)
                : TextSpan(
                    text: part.text,
                    style: link,
                    recognizer: _recognizer(links++, part.onTap!),
                  ),
        ],
      ),
      align: widget.align,
    );
  }
}
