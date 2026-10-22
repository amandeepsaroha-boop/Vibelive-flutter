import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// RN AppWebViewScreen header: back, title + host (lock / "Not secure"),
/// reload, open in browser.
class WebviewHeader extends StatelessWidget {
  const WebviewHeader({
    super.key,
    required this.title,
    required this.host,
    required this.secure,
    required this.onBack,
    required this.onReload,
    required this.onExternal,
  });

  /// '' ⇒ the host, else "Web page".
  final String title;
  final String? host;
  final bool secure;
  final VoidCallback onBack;
  final VoidCallback onReload;
  final VoidCallback onExternal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = c.isDark ? AppColors.whiteA(0.5) : AppColors.blackA(0.5);
    final border = c.isDark ? AppColors.whiteA(0.1) : AppColors.blackA(0.1);
    final h = host ?? '';

    Widget icon(IconData data, double size, VoidCallback onTap, String label) =>
        Pressable(
          onPressed: onTap,
          semanticLabel: context.t(label),
          child: SizedBox(
            width: 38.ms,
            height: 38.ms,
            child: Icon(data, size: size.ms, color: c.text),
          ),
        );

    final heading = title.isNotEmpty
        ? CText.raw(title, size: 15, weight: FontWeight.w700, maxLines: 1)
        : h.isNotEmpty
        ? CText.raw(h, size: 15, weight: FontWeight.w700, maxLines: 1)
        : const CText(
            'resources:webview.fallback_title',
            size: 15,
            weight: FontWeight.w700,
            maxLines: 1,
          );

    return Container(
      height: 54.ms,
      padding: EdgeInsets.symmetric(horizontal: 8.ms),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 0.5)),
      ),
      child: Row(
        children: [
          icon(LucideIcons.chevronLeft, 24, onBack, 'actions.back'),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.ms),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  if (h.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          secure ? LucideIcons.lock : LucideIcons.triangleAlert,
                          size: 10.ms,
                          color: secure
                              ? BrandColors.lime
                              : StatusColors.dangerRed,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: secure
                              ? CText.raw(
                                  h,
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: muted,
                                  maxLines: 1,
                                )
                              : CText(
                                  'resources:webview.not_secure',
                                  variables: {'host': h},
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color: muted,
                                  maxLines: 1,
                                ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          icon(LucideIcons.refreshCw, 18, onReload, 'resources:webview.reload'),
          icon(
            LucideIcons.externalLink,
            18,
            onExternal,
            'resources:webview.open_browser',
          ),
        ],
      ),
    );
  }
}
