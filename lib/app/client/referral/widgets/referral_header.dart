import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_loader.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/referral_palette.dart';

/// Back · "Referral" · refresh (RN ReferralScreen header). Only the refresh
/// button listens to [refreshing].
class ReferralHeader extends StatelessWidget {
  const ReferralHeader({
    super.key,
    required this.refreshing,
    required this.onRefresh,
  });

  final ValueListenable<bool> refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = ReferralPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 6.ms),
      child: Row(
        children: [
          _HeaderButton(
            semanticLabel: context.t('actions.back'),
            border: p.border,
            fill: p.soft,
            // Opened from a push or link with nothing below: go Home.
            onPressed: () => Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : context.go(AppRoutes.home),
            child: Icon(LucideIcons.chevronLeft, size: 20.ms, color: p.text),
          ),
          Expanded(
            child: CText(
              'client:referral.title',
              size: 18,
              weight: FontWeight.w900,
              color: p.text,
              align: TextAlign.center,
              maxLines: 1,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: refreshing,
            builder: (context, busy, _) => Opacity(
              opacity: busy ? 0.7 : 1,
              child: _HeaderButton(
                semanticLabel: context.t('client:referral.refresh'),
                border: p.accentBorder,
                fill: p.accentFill,
                onPressed: busy ? null : onRefresh,
                child: busy
                    ? CLoader(size: 16.ms, strokeWidth: 2, color: p.accent)
                    : Icon(
                        LucideIcons.refreshCcw,
                        size: 16.ms,
                        color: p.accent,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.semanticLabel,
    required this.border,
    required this.fill,
    required this.onPressed,
    required this.child,
  });

  final String semanticLabel;
  final Color border;
  final Color fill;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    semanticLabel: semanticLabel,
    child: Container(
      width: 42.ms,
      height: 42.ms,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14.ms),
        border: Border.all(color: border),
      ),
      child: child,
    ),
  );
}
