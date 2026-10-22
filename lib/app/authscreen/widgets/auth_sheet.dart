import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/pressable.dart';
import 'auth_theme.dart';

/// Bottom sheet for the email / mobile sign-in steps (RN `AuthSheet`):
/// dimmed backdrop, grabber, header row (an optional [headerLeft] and the
/// close button) and scrolling content.
///
/// It lives inside the login screen's own Stack rather than a modal route:
/// the controller opens it itself (a social user who must add a phone
/// number) and sign-in replaces the whole stack while it is up. Place it in
/// a Scaffold body that resizes for the keyboard, so it sits on top of it.
///
/// [visible] fades it in / out (RN Modal `fade`); the sheet slides up as it
/// appears. A null [onClose] removes the close button and the
/// tap-outside close (RN `dismissible={false}`).
///
/// Performance: the slide moves a cached layer (the sheet is painted once,
/// not on every frame), and only a leaf reads the bottom inset. A field that
/// autofocuses when the sheet opens should wait [duration] (see
/// `CInput.autofocusDelay`): raising the keyboard mid-slide stalls frames.
class AuthSheet extends StatelessWidget {
  const AuthSheet({
    super.key,
    required this.visible,
    required this.onClose,
    required this.headerLeft,
    required this.child,
  });

  final bool visible;
  final VoidCallback? onClose;
  final Widget? headerLeft;
  final Widget child;

  /// Fade in / out and slide-in time.
  static const duration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: visible
          // No key: a reopen during the fade-out must not clash with the
          // outgoing frame.
          ? _SheetFrame(onClose: onClose, headerLeft: headerLeft, child: child)
          : const SizedBox.shrink(),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.onClose,
    required this.headerLeft,
    required this.child,
  });

  final VoidCallback? onClose;
  final Widget? headerLeft;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    final close = context.t('actions.close');
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          button: onClose != null,
          label: onClose == null ? null : close,
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: t.backdrop),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // RN `maxHeight: '92%'`: the sheet may take 92 parts, never the
            // top 8 (a loose Flexible only uses what its content needs).
            const Expanded(flex: 8, child: SizedBox.shrink()),
            Flexible(
              flex: 92,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 420.ms, end: 0),
                duration: AuthSheet.duration,
                curve: Curves.easeInOut,
                builder: (_, dy, sheet) =>
                    Transform.translate(offset: Offset(0, dy), child: sheet),
                // Painted once: each slide frame only moves this layer.
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.sheet,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(30.ms),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x2E000000), // black 18%
                          blurRadius: 20.ms,
                          offset: Offset(0, -4.ms),
                        ),
                      ],
                    ),
                    child: _BottomSafe(
                      top: 10.ms,
                      extra: 20.ms,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40.ms,
                            height: 5.ms,
                            decoration: BoxDecoration(
                              color: t.line,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          Container(
                            height: 38.ms,
                            margin: EdgeInsets.only(top: 6.ms),
                            padding: EdgeInsets.symmetric(horizontal: 18.ms),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _Slot(child: headerLeft),
                                _Slot(
                                  child: onClose == null
                                      ? null
                                      : AuthSheetIconButton(
                                          icon: LucideIcons.x,
                                          iconSize: 18,
                                          label: close,
                                          onPressed: onClose!,
                                        ),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                24.ms,
                                4.ms,
                                24.ms,
                                0,
                              ),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The sheet's padding, over the home indicator. Its own widget: the inset
/// changes while the keyboard moves, and only this padding depends on it.
class _BottomSafe extends StatelessWidget {
  const _BottomSafe({
    required this.top,
    required this.extra,
    required this.child,
  });

  final double top;

  /// Space above the home indicator.
  final double extra;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: top,
      bottom: MediaQuery.paddingOf(context).bottom + extra,
    ),
    child: child,
  );
}

class _Slot extends StatelessWidget {
  const _Slot({required this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: 36.ms),
    child: Center(child: child),
  );
}

/// Round icon button for the sheet header (Close, Back on the code step).
class AuthSheetIconButton extends StatelessWidget {
  const AuthSheetIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconSize = 20,
  });

  final IconData icon;
  final double iconSize;

  /// Translated accessibility label.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AuthTheme.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      child: Container(
        width: 36.ms,
        height: 36.ms,
        decoration: BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
        child: Icon(icon, size: iconSize.ms, color: t.ink),
      ),
    );
  }
}
