import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/pressable.dart';
import 'auth_theme.dart';

/// One sign-in choice (RN `AuthOptionButton`): pill with the provider icon,
/// a hairline divider, a centred label and a chevron. [tinted] is the
/// purple-washed variant ("Continue with mobile number"). [label] is an
/// i18n key.
class AuthOptionButton extends StatelessWidget {
  const AuthOptionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.disabled = false,
    this.tinted = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final bool disabled;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    final inactive = disabled || loading;
    final text = context.t(label);
    return Opacity(
      opacity: disabled && !loading ? 0.5 : 1,
      child: Pressable(
        onPressed: inactive ? null : onPressed,
        activeOpacity: 0.8,
        semanticLabel: text,
        child: Container(
          height: 58.ms,
          padding: EdgeInsets.only(left: 18.ms, right: 16.ms),
          decoration: BoxDecoration(
            color: tinted ? t.accentSoft : t.card,
            borderRadius: BorderRadius.circular(29.ms),
            border: Border.all(color: tinted ? t.accentBorder : t.cardBorder),
            boxShadow: tinted || t.dark
                ? null
                : [
                    BoxShadow(
                      color: const Color(0x141B1340), // #1B1340 at 8%
                      blurRadius: 10.ms,
                      offset: Offset(0, 4.ms),
                    ),
                  ],
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 30.ms,
                child: Center(child: icon),
              ),
              Container(
                width: 1,
                height: 28.ms,
                margin: EdgeInsets.only(left: 14.ms),
                color: tinted ? t.accentBorder : t.line,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.ms),
                  child: Center(
                    child: loading
                        ? SizedBox.square(
                            dimension: 20,
                            child: RepaintBoundary(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: t.accent,
                              ),
                            ),
                          )
                        // RN adjustsFontSizeToFit (min 0.85) on narrow phones.
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ExcludeSemantics(
                              child: Text(
                                text,
                                maxLines: 1,
                                textScaler: TextScaler.noScaling,
                                style: AuthTheme.text(
                                  16,
                                  color: t.ink,
                                  weight: FontWeight.w700,
                                  spacing: -0.2,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 20.ms,
                color: tinted ? t.accent : t.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
