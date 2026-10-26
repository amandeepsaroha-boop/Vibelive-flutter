import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_button.dart';
import '../../../component/c_loader.dart';
import '../../../component/c_text.dart';
import '../../../component/confetti_burst.dart';
import '../helper/topup_celebration.dart';
import '../helper/topup_checkout.dart';
import '../helper/wallet_palette.dart';

/// RN "Payment Successful / Received / Failed" modal (fade, black 60%). A
/// success celebrates in the app (coin sound, haptic, one confetti burst)
/// instead of a push.
Future<void> showPaymentStatus(BuildContext context, TopUpStatus status) {
  final success = status.result == TopUpResult.success;
  if (success) unawaited(TopupCelebration.celebrate());
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'payment-status',
    barrierColor: AppColors.blackA(0.6),
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (_, _, _) => success
        ? Stack(
            children: [
              _StatusCard(status: status),
              const Positioned.fill(child: ConfettiBurst()),
            ],
          )
        : _StatusCard(status: status),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final TopUpStatus status;

  /// RN: the gateway's own reason, unless it is the bare default.
  static const _genericReason = 'Payment failed';

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final (icon, color, tile, title) = switch (status.result) {
      TopUpResult.success => (
        LucideIcons.circleCheck,
        BrandColors.lime,
        const Color(0x2479FF3F),
        'payment:status.success_title',
      ),
      TopUpResult.pending => (
        LucideIcons.clock,
        const Color(0xFFFAAD14),
        const Color(0x24FAAD14),
        'payment:verification.pending_title',
      ),
      TopUpResult.failure => (
        LucideIcons.circleX,
        WalletPalette.error,
        const Color(0x24FF4D4F),
        'payment:status.failure_title',
      ),
    };
    final raw = status.message;
    final rawReason = raw != null && raw.isNotEmpty && raw != _genericReason
        ? raw
        : null;
    final messageKey = switch (status.result) {
      TopUpResult.success => 'payment:status.success',
      _ => status.messageKey ?? 'payment:status.failure',
    };

    return SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24.ms),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(maxWidth: 340.ms),
              padding: EdgeInsets.all(32.ms),
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(32.ms),
                border: Border.all(color: p.cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72.ms,
                    height: 72.ms,
                    decoration: BoxDecoration(
                      color: tile,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 36.ms, color: color),
                  ),
                  SizedBox(height: 16.ms),
                  CText(
                    title,
                    size: 20,
                    weight: FontWeight.w900,
                    color: p.text,
                    align: TextAlign.center,
                  ),
                  SizedBox(height: 8.ms),
                  if (status.result == TopUpResult.failure && rawReason != null)
                    CText.raw(
                      rawReason,
                      size: 14,
                      weight: FontWeight.w600,
                      height: 20,
                      color: p.muted,
                      align: TextAlign.center,
                    )
                  else
                    CText(
                      messageKey,
                      size: 14,
                      weight: FontWeight.w600,
                      height: 20,
                      color: p.muted,
                      align: TextAlign.center,
                    ),
                  SizedBox(height: 24.ms),
                  CButton(
                    title: 'payment:status.continue',
                    showArrow: false,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Verifying Payment..." over the whole screen while [visible] is true
/// (RN verifying modal). Blocks touches and back meanwhile.
class VerifyingOverlay extends StatelessWidget {
  const VerifyingOverlay({super.key, required this.visible});

  final ValueListenable<bool> visible;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, on, _) => PopScope(
        canPop: !on,
        child: IgnorePointer(
          ignoring: !on,
          child: AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: on ? const _VerifyingCard() : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _VerifyingCard extends StatelessWidget {
  const _VerifyingCard();

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return ColoredBox(
      color: AppColors.blackA(0.7),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24.ms),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(maxWidth: 300.ms),
            padding: EdgeInsets.all(28.ms),
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius: BorderRadius.circular(24.ms),
              border: Border.all(color: p.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(child: CLoader(size: 36, color: p.accent)),
                SizedBox(height: 16.ms),
                CText(
                  'payment:status.verifying_title',
                  size: 17,
                  weight: FontWeight.w900,
                  color: p.text,
                  align: TextAlign.center,
                ),
                SizedBox(height: 8.ms),
                CText(
                  'payment:status.verifying',
                  size: 13,
                  weight: FontWeight.w500,
                  height: 18,
                  color: p.muted,
                  align: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
