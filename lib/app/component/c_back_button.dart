import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import 'pressable.dart';

/// RN `BackButton`: rounded square with a chevron-back.
///
/// Without [onPressed] it pops the current route. With [onPressed], the
/// Android hardware back key runs the same callback while this screen is on
/// top (RN bound it only for a custom onPress, only on Android).
class CBackButton extends StatelessWidget {
  const CBackButton({
    super.key,
    this.onPressed,
    this.color,
    this.size = 24,
    this.boxSize = 40,
    this.radius = 12,
  });

  final VoidCallback? onPressed;
  final Color? color;

  /// Chevron size.
  final double size;

  /// Unscaled side of the square, and its corner radius.
  final double boxSize;
  final double radius;

  void _handle(BuildContext context) {
    if (onPressed != null) {
      onPressed!();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = Pressable(
      onPressed: () => _handle(context),
      semanticLabel: context.t('actions.back'),
      hitPadding: const EdgeInsets.all(4),
      child: Container(
        width: boxSize.ms,
        height: boxSize.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: c.border),
        ),
        child: Icon(
          LucideIcons.chevronLeft,
          size: size,
          color: color ?? c.text,
          weight: 700,
        ),
      ),
    );

    if (onPressed == null || !Platform.isAndroid) return button;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onPressed!();
      },
      child: button,
    );
  }
}
