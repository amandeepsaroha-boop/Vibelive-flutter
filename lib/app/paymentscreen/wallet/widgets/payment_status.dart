import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_button.dart';
import '../../../component/c_text.dart';
import '../helper/topup_celebration.dart';
import '../helper/topup_checkout.dart';
import '../helper/wallet_palette.dart';
import 'payment_status_motion.dart';

/// RN "Payment Successful / Received / Failed" modal (black 60%): the card
/// fades in with a slight lift. A success celebrates in the app instead of a
/// push: the painted burst, and the coin sound + haptic the moment its check
/// lands. The text follows it in; failure and pending show theirs at once.
///
/// [titleKey] / [messageKey] replace the wallet wording, for any payment
/// (e.g. the Verification Badge fee); a failure's gateway reason still shows.
Future<void> showPaymentStatus(
  BuildContext context,
  TopUpStatus status, {
  String? titleKey,
  String? messageKey,
}) => showGeneralDialog<void>(
  context: context,
  routeSettings: ScreenTracker.sheet('payment_status_dialog'),
  barrierDismissible: true,
  barrierLabel: 'payment-status',
  barrierColor: AppColors.blackA(0.6),
  transitionDuration: const Duration(milliseconds: 260),
  transitionBuilder: (_, anim, _, child) {
    final eased = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: eased,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(eased),
        child: child,
      ),
    );
  },
  pageBuilder: (_, _, _) =>
      _StatusCard(status: status, titleKey: titleKey, messageKey: messageKey),
);

class _StatusCard extends StatefulWidget {
  const _StatusCard({required this.status, this.titleKey, this.messageKey});
  final TopUpStatus status;
  final String? titleKey;
  final String? messageKey;

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  /// RN: the gateway's own reason, unless it is the bare default.
  static const _genericReason = 'Payment failed';

  late final _revealed = ValueNotifier<bool>(
    widget.status.result != TopUpResult.success,
  );

  void _landed() {
    if (_revealed.value) return;
    _revealed.value = true;
    PaymentEvents.celebrationShown();
    unawaited(TopupCelebration.celebrate());
  }

  @override
  void dispose() {
    _revealed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    final status = widget.status;
    final title =
        widget.titleKey ??
        switch (status.result) {
          TopUpResult.success => 'payment:status.success_title',
          TopUpResult.pending => 'payment:verification.pending_title',
          TopUpResult.failure => 'payment:status.failure_title',
        };
    final art = switch (status.result) {
      TopUpResult.success => PaymentSuccessBurst(onLanded: _landed),
      TopUpResult.pending => const PaymentConfirmingRing(),
      TopUpResult.failure => const PaymentStatusMark(
        kind: PaymentMarkKind.failed,
      ),
    };
    final raw = status.message;
    final rawReason = raw != null && raw.isNotEmpty && raw != _genericReason
        ? raw
        : null;
    final messageKey =
        widget.messageKey ??
        switch (status.result) {
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
              padding: EdgeInsets.fromLTRB(28.ms, 18.ms, 28.ms, 28.ms),
              decoration: BoxDecoration(
                color: p.bg,
                borderRadius: BorderRadius.circular(32.ms),
                border: Border.all(color: p.cardBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  art,
                  // Rebuilds once, when the check lands.
                  ValueListenableBuilder<bool>(
                    valueListenable: _revealed,
                    builder: (_, shown, child) => AnimatedSlide(
                      offset: shown ? Offset.zero : const Offset(0, 0.08),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: shown ? 1 : 0,
                        duration: const Duration(milliseconds: 320),
                        child: child,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CText(
                          title,
                          size: 20,
                          weight: FontWeight.w900,
                          color: p.text,
                          align: TextAlign.center,
                        ),
                        SizedBox(height: 8.ms),
                        if (status.result == TopUpResult.failure &&
                            rawReason != null)
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
                const PaymentConfirmingRing(size: 96),
                SizedBox(height: 8.ms),
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
