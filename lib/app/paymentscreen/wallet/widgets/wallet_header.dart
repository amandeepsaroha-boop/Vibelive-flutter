import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/wallet_palette.dart';
import 'bank_sheet.dart';

/// Icon button of the wallet screens (RN header buttons: ms42, bordered,
/// soft fill). Rounded square (radius ms14) for X; [circle] for arrows.
class WalletIconButton extends StatelessWidget {
  const WalletIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 42,
    this.radius = 14,
    this.iconSize = 20,
    this.circle = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final double size;
  final double radius;
  final double iconSize;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    // One opaque shape: a translucent fill under a translucent border
    // anti-aliases unevenly along a curve (looked broken on device).
    final fill = Color.alphaBlend(p.soft, p.bg);
    final side = BorderSide(color: Color.alphaBlend(p.cardBorder, fill));
    final box = size.ms.roundToDouble();
    return Pressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      child: SizedBox.square(
        dimension: box,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: fill,
            shape: circle
                ? CircleBorder(side: side)
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      radius.ms.roundToDouble(),
                    ),
                    side: side,
                  ),
          ),
          child: Center(
            child: Icon(icon, size: iconSize.ms, color: p.text),
          ),
        ),
      ),
    );
  }
}

class WalletHeader extends StatelessWidget {
  const WalletHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 8.ms, 16.ms, 16.ms),
      child: Row(
        children: [
          WalletIconButton(
            icon: LucideIcons.arrowLeft,
            circle: true,
            semanticLabel: context.t('payment:wallet.back'),
            // Opened from a push or link with nothing below: go Home.
            onPressed: () => Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : context.go(AppRoutes.home),
          ),
          SizedBox(width: 14.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  'payment:wallet.title',
                  size: 18,
                  weight: FontWeight.w900,
                  letterSpacing: -0.2,
                  color: p.text,
                  maxLines: 1,
                ),
                SizedBox(height: 2.ms),
                CText(
                  'payment:wallet.subtitle',
                  size: 9,
                  weight: FontWeight.w900,
                  letterSpacing: 2,
                  color: p.accent,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          SizedBox(width: 10.ms),
          const BankButton(),
        ],
      ),
    );
  }
}
