import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/pressable.dart';
import '../helper/call_actions.dart';
import '../helper/call_controller.dart';
import '../helper/call_session.dart';
import '../helper/engine/call_engine.dart';
import 'helper/call_format.dart';
import 'helper/call_guard.dart';
import 'helper/call_select.dart';
import 'helper/call_track.dart';
import 'incoming/incoming_actions.dart';

/// RN `CallControls`: floating bar with mic · (camera) · speaker · (flip) ·
/// hang-up — 3 buttons on audio, 5 on video. Hidden once the call is over.
/// Hang-up is held 2.5 s after the call is placed / answered and again when
/// it connects (no visual change, as RN), counted from the phase change.
class CallControls extends HookWidget {
  const CallControls({super.key});

  @override
  Widget build(BuildContext context) {
    final (over, video, connected, callId, since) = useCallSelect(
      (s) => (
        isCallOver(s.phase),
        s.isVideo,
        s.phase.isLive,
        s.callId,
        s.phaseSince,
      ),
    );
    // Held from the start of each guard phase (pre / connected), not from
    // mount: coming back to a running call keeps what is left (U10).
    final armed = useArmedAfter(callGuardDelay, [callId, connected], since);
    if (over) return const SizedBox.shrink();

    final pad = MediaQuery.paddingOf(context);
    final b = (video ? 50 : 58).sw;
    final i = (video ? 23 : 26).ms;
    final engine = CallEngine.instance;
    CallMedia media() => engine.media.value;

    /// [toggle], then the new state to analytics.
    Future<void> Function() tracked(
      Future<void> Function() toggle,
      void Function(CallInfo call, CallMedia m) log,
    ) => () async {
      await toggle();
      log(callInfoOf(CallController.instance.value), media());
    };
    return Positioned(
      left: 14.sw,
      right: 14.sw,
      bottom: math.max(pad.bottom, 10) + 10.vs,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.sw, vertical: 12.vs),
        decoration: BoxDecoration(
          color: AppColors.blackA(0.92),
          borderRadius: BorderRadius.circular(30.sw),
          border: Border.all(color: AppColors.whiteA(0.12)),
          boxShadow: [
            BoxShadow(
              color: AppColors.blackA(0.35),
              blurRadius: 24.sw,
              offset: Offset(0, 10.vs),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Toggle(
              size: b,
              label: 'call:controls.mute',
              onPressed: tracked(
                engine.toggleMute,
                (c, m) => CallUiEvents.muteToggled(c, muted: m.muted),
              ),
              select: (m) => m.muted,
              icon: (on) => on ? LucideIcons.micOff : LucideIcons.mic,
              iconSize: i,
              greenWhenOn: true,
            ),
            if (video)
              _Toggle(
                size: b,
                label: 'call:controls.camera',
                onPressed: tracked(
                  engine.toggleVideo,
                  (c, m) => CallUiEvents.cameraToggled(c, on: !m.localVideoOff),
                ),
                select: (m) => m.localVideoOff,
                icon: (off) => off ? LucideIcons.videoOff : LucideIcons.video,
                iconSize: i,
              ),
            _Toggle(
              size: b,
              label: 'call:controls.speaker',
              onPressed: tracked(
                engine.toggleSpeaker,
                (c, m) => CallUiEvents.speakerToggled(c, on: m.speakerOn),
              ),
              select: (m) => m.speakerOn,
              icon: (_) => LucideIcons.volume2,
              iconSize: i,
              greenWhenOn: true,
            ),
            if (video)
              _Round(
                size: b,
                label: 'call:controls.flip',
                onPressed: () => unawaited(
                  tracked(
                    engine.flipCamera,
                    (c, m) => CallUiEvents.cameraFlipped(c, front: m.frontCamera),
                  )(),
                ),
                child: Icon(
                  LucideIcons.refreshCw,
                  size: i - 2,
                  color: AppColors.slate200,
                  weight: 500,
                ),
              ),
            _Round(
              size: b,
              label: 'call:controls.hangup',
              onPressed: armed ? () => _hangup() : null,
              color: AppColors.red,
              shadow: AppColors.red.withValues(alpha: 0.4),
              child: HangupGlyph(size: i + 2),
            ),
          ],
        ),
      ),
    );
  }
}

/// The red button: analytics, then the hang-up.
void _hangup() {
  final s = CallController.instance.value;
  CallUiEvents.hangupTapped(
    callInfoOf(s),
    elapsedSeconds: s.everConnected ? s.durationSeconds() : null,
  );
  unawaited(CallActions.hangup());
}

/// A control that shows one media flag; rebuilds only when that flag
/// changes.
class _Toggle extends HookWidget {
  const _Toggle({
    required this.size,
    required this.label,
    required this.onPressed,
    required this.select,
    required this.icon,
    required this.iconSize,
    this.greenWhenOn = false,
  });

  final double size;
  final String label;
  final Future<void> Function() onPressed;
  final bool Function(CallMedia m) select;
  final IconData Function(bool on) icon;
  final double iconSize;

  /// Mic muted / speaker on turn green (#27AE60); the camera never does.
  final bool greenWhenOn;

  @override
  Widget build(BuildContext context) {
    final on = useMediaSelect(select);
    return _Round(
      size: size,
      label: label,
      onPressed: () => unawaited(onPressed()),
      child: Icon(
        icon(on),
        size: iconSize,
        color: greenWhenOn && on ? AppColors.green : AppColors.slate200,
        weight: 500,
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.size,
    required this.label,
    required this.onPressed,
    required this.child,
    this.color,
    this.shadow,
  });

  final double size;
  final String label;

  /// Null while held (hang-up guard): no taps, no dimming.
  final VoidCallback? onPressed;
  final Widget child;

  /// Filled (hang-up); otherwise the 8 % white secondary style.
  final Color? color;
  final Color? shadow;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onPressed,
    activeOpacity: 0.86,
    semanticLabel: context.t(label),
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? AppColors.whiteA(0.08),
        border: color == null
            ? Border.all(color: AppColors.whiteA(0.12))
            : null,
        boxShadow: shadow == null
            ? null
            : [BoxShadow(color: shadow!, blurRadius: 10)],
      ),
      child: child,
    ),
  );
}
