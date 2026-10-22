import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/keyboard_inset.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../component/status_bar_style.dart';
import '../onboarding/helper/host_palette.dart';

/// Page frame of the Host Hub screens: back chevron + title, the body, and
/// an optional sticky action above the home indicator. Flat, theme colors.
class HostPage extends StatelessWidget {
  const HostPage({
    super.key,
    required this.title,
    required this.body,
    this.bottom,
    this.trailing,
  });

  /// i18n key.
  final String title;
  final Widget body;
  final Widget? bottom;
  final Widget? trailing;

  /// Back, or the ME tab when the screen was opened directly (a link).
  static void leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('${AppRoutes.home}?tab=me');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: p.bg,
        resizeToAvoidBottomInset: false,
        body: KeyboardInset(
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.ms, 6.ms, 16.ms, 6.ms),
                  child: Row(
                    children: [
                      Pressable(
                        onPressed: () => leave(context),
                        semanticLabel: context.t('hostflow:back'),
                        hitPadding: EdgeInsets.all(4.ms),
                        child: Container(
                          width: 42.ms,
                          height: 42.ms,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.neutral,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.chevronLeft,
                            size: 22.ms,
                            color: p.text,
                          ),
                        ),
                      ),
                      SizedBox(width: 12.ms),
                      Expanded(
                        child: CText(
                          title,
                          size: 18,
                          weight: FontWeight.w700,
                          color: p.text,
                          maxLines: 1,
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              ),
              Expanded(child: body),
              if (bottom != null)
                SafeArea(
                  top: false,
                  minimum: EdgeInsets.only(bottom: 12.ms),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.ms, 10.ms, 20.ms, 0),
                    child: bottom,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum HostTone { info, success, warning, danger }

/// Icon + title + message on a tinted card (status banners).
class HostToneCard extends StatelessWidget {
  const HostToneCard({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.message,
    this.translateMessage = true,
    this.titleVariables,
  });

  final HostTone tone;
  final IconData icon;

  /// i18n keys ([message] literal when [translateMessage] is false).
  final String title;
  final String? message;
  final bool translateMessage;
  final Map<String, dynamic>? titleVariables;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final (color, bg) = switch (tone) {
      HostTone.success => (p.success, p.successTint),
      HostTone.danger => (p.danger, p.dangerTint),
      HostTone.warning => (p.warning, p.warningTint),
      HostTone.info => (p.accent, p.tint),
    };
    final m = message;
    return Container(
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.ms),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22.ms, color: color),
          SizedBox(width: 12.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  title,
                  variables: titleVariables,
                  size: 15,
                  weight: FontWeight.w800,
                  color: p.text,
                ),
                if (m != null) ...[
                  SizedBox(height: 4.ms),
                  translateMessage
                      ? CText(
                          m,
                          size: 13,
                          height: 18,
                          weight: FontWeight.w500,
                          color: p.muted,
                        )
                      : CText.raw(
                          m,
                          size: 13,
                          height: 18,
                          weight: FontWeight.w500,
                          color: p.muted,
                        ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// First-load placeholder of a Host Hub screen.
class HostPageSkeleton extends StatelessWidget {
  const HostPageSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(20.ms),
    child: Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBox(height: 90.ms, radius: 16),
          SizedBox(height: 14.ms),
          SkeletonBox(height: 56.ms, radius: 14),
          SizedBox(height: 10.ms),
          SkeletonBox(height: 56.ms, radius: 14),
          SizedBox(height: 10.ms),
          const SkeletonLines(lines: 3, height: 14),
        ],
      ),
    ),
  );
}
