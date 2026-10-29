import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/call_ui_events.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../helper/call_actions.dart';
import '../call_motion_widgets.dart';
import '../helper/call_format.dart';
import '../helper/call_guard.dart';
import '../helper/call_select.dart';
import '../helper/call_track.dart';
import '../helper/call_ui_state.dart';
import 'incoming_safety_card.dart';

/// Bottom of the incoming screen (RN action area): the safety card, then
/// Decline / Accept. Decline is held for 2.5 s after mount with no visual
/// change (RN `DECLINE_GUARD_MS`); Accept never is. One action at a time.
class IncomingActions extends HookWidget {
  const IncomingActions({super.key});

  @override
  Widget build(BuildContext context) {
    // Re-armed when a different ring replaces this one (U11).
    final callId = useCallSelect((s) => s.callId);
    final declineArmed = useArmedAfter(callGuardDelay, [callId]);
    final inFlight = useInFlight();
    final busy = useState<IncomingSafety?>(null);
    final name = useCallSelect((s) => nonEmpty(s.remote.name));
    final drawn = CallScope.of(context).session;

    Future<void> safety(IncomingSafety kind) async {
      if (busy.value != null || inFlight.busy) return;
      final block = kind == IncomingSafety.block;
      // The caller on screen, taken BEFORE the confirm: the ring may end
      // while it is up (U2).
      final call = drawn.value;
      final info = callInfoOf(call);
      CallUiEvents.incomingSafetyTapped(info, action: kind.name);
      final who = name ?? context.t('call:incoming.this_caller');
      final ok = await CAlert.show(
        context: context,
        title: block
            ? 'call:incoming.block_title'
            : 'call:incoming.report_title',
        message: block
            ? 'call:incoming.block_message'
            : 'call:incoming.report_message',
        variables: {'name': who},
        primaryLabel: block ? 'call:incoming.block' : 'call:incoming.report',
        secondaryLabel: 'actions.cancel',
        variant: CAlertVariant.error,
      );
      CallUiEvents.safetyConfirm(
        action: kind.name,
        source: 'incoming',
        confirmed: ok == true,
        call: info,
      );
      if (ok != true) return;
      // Confirmed: the block / report runs even when the ring ended during
      // the confirm and took this screen with it (U2). The logic declines
      // only a call still ringing and always files against the caller.
      if (context.mounted) busy.value = kind;
      // Declines first; RN only logged a failed block / report.
      await inFlight.run(() async {
        final done = block
            ? await CallActions.declineAndBlock(call: call)
            : await CallActions.declineAndReport(call: call);
        CallUiEvents.safetyAction(
          action: kind.name,
          source: 'incoming',
          outcome: done ? 'done' : 'failed',
          call: info,
        );
      });
      if (context.mounted) busy.value = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IncomingSafetyCard(busy: busy.value, onAction: safety),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntryIn(
                delay: const Duration(milliseconds: 500),
                fromDy: 20.vs,
                child: _DeclineButton(
                  onPressed: declineArmed
                      ? () => inFlight.run(() {
                          CallUiEvents.declineTapped(callInfoOf(drawn.value));
                          return CallActions.decline();
                        })
                      : null,
                ),
              ),
              EntryIn(
                delay: const Duration(milliseconds: 700),
                fromDy: 20.vs,
                child: _AcceptButton(
                  onPressed: () => inFlight.run(() {
                    CallUiEvents.acceptTapped(callInfoOf(drawn.value));
                    return CallActions.accept();
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Phone glyph rotated 135° (RN decline / hang-up). Static on purpose: the
/// old spin looked like vibrating.
class HangupGlyph extends StatelessWidget {
  const HangupGlyph({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: 135 * math.pi / 180,
    child: Icon(
      LucideIcons.phone,
      size: size,
      color: AppColors.white,
      weight: 600,
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.keyName, {required this.color});
  final String keyName;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: 16.vs),
    child: CText(
      keyName,
      color: color,
      weight: FontWeight.w900,
      uppercase: true,
      size: 10,
      letterSpacing: 4.2,
      maxLines: 1,
    ),
  );
}

class _DeclineButton extends StatelessWidget {
  const _DeclineButton({required this.onPressed});

  /// Null while the guard holds (RN `disabled`, no visual change).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final d = 80.sw;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pressable(
          onPressed: onPressed,
          activeOpacity: 0.8,
          semanticLabel: context.t('call:incoming.decline'),
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: AppColors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withValues(alpha: 0.4),
                  blurRadius: 15,
                ),
              ],
            ),
            child: Center(child: HangupGlyph(size: 30.ms)),
          ),
        ),
        _Label('call:incoming.decline', color: AppColors.whiteA(0.4)),
      ],
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final d = 80.sw;
    // Two greens, as RN: #79FF3F fill, #A8EC4A label.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: d,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: PingPong(
                    leg: Duration(milliseconds: 2000),
                    scaleTo: 1.5,
                    opacityFrom: 0.5,
                    opacityTo: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: BrandColors.vibeLime,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Pressable(
                  onPressed: onPressed,
                  activeOpacity: 0.8,
                  semanticLabel: context.t('call:incoming.accept'),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: BrandColors.vibeLime,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: BrandColors.vibeLimeA(0.5),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Center(
                      child: HoldBlink(
                        leg: const Duration(milliseconds: 1500),
                        low: 1,
                        high: 1.1,
                        of: BlinkOf.scale,
                        child: Icon(
                          LucideIcons.phone,
                          size: 30.ms,
                          color: AppColors.black,
                          weight: 600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const _Label('call:incoming.accept', color: BrandColors.lime),
      ],
    );
  }
}
