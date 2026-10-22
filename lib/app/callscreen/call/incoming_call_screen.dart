import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import '../helper/call_actions.dart';
import '../helper/call_controller.dart';
import '../helper/call_session.dart';
import 'call_permission_bar.dart';
import 'call_video_view.dart';
import 'helper/call_nav.dart';
import 'helper/call_select.dart';
import 'helper/call_ui_state.dart';
import 'incoming/incoming_actions.dart';
import 'incoming/incoming_intro.dart';

/// `/call/incoming` (RN `IncomingCallScreen`): who is calling, the safety
/// card, Decline / Accept. Always dark with light status-bar icons; no
/// swipe-back. Leaves for `/call` once the call is answered (here or
/// elsewhere) and for Home once it stops ringing.
class IncomingCallScreen extends HookWidget {
  const IncomingCallScreen({super.key});

  /// RN: exits are ignored this long after mount (payload hydration gaps),
  /// unless the call was already seen ringing.
  static const bootstrap = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    final sticky = useMemoized(
      () => StickySession(CallController.instance.session),
    );
    useEffect(() => sticky.dispose, [sticky]);
    _useIncomingExits(context);
    // Plain #050508 until there is a call to show (RN never drew a partial
    // incoming UI).
    final hasCall = useSelect(sticky, (s) => s.phase != CallPhase.idle);

    return PopScope(
      canPop: false,
      child: ThemedStatusBar(
        darkBackground: true,
        child: Material(
          color: DarkColors.bg,
          child: CallScope(
            session: sticky,
            child: hasCall ? const _IncomingBody() : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// RN status effect: accepted / ongoing → `/call`; idle / ended → Home (via
/// the logic's once-only exit), but only after the bootstrap or once the
/// call was seen ringing.
void _useIncomingExits(BuildContext context) {
  useEffect(() {
    final session = CallController.instance.session;
    var bootstrapped = false;
    var sawRinging = false;
    var done = false;
    String? shown; // the call this screen showed (stale-exit guard)

    void check() {
      if (done || !context.mounted) return;
      final phase = session.value.phase;
      shown = session.value.callId ?? shown;
      if (phase == CallPhase.ringing) sawRinging = true;
      if (phase.isLive) {
        done = true;
        goToCallScreen(context);
      } else if ((phase == CallPhase.idle || phase == CallPhase.ended) &&
          (bootstrapped || sawRinging)) {
        done = true;
        CallActions.exitToHome(callId: shown);
      }
    }

    final timer = Timer(IncomingCallScreen.bootstrap, () {
      bootstrapped = true;
      check();
    });
    session.addListener(check);
    // The call may have moved on before this screen mounted (answered from
    // CallKit): never navigate during this build.
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
    return () {
      timer.cancel();
      session.removeListener(check);
    };
  }, const []);
}

class _IncomingBody extends HookWidget {
  const _IncomingBody();

  @override
  Widget build(BuildContext context) {
    final (video, company) = useCallSelect(
      (s) => (s.isVideo, s.remote.isCompany),
    );
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        const VibeBackground(dark: true),
        if (video) const _OwnPreview(),
        // RN main SafeAreaView: a 28 % scrim over the own camera on a video
        // call.
        if (video) ColoredBox(color: AppColors.blackA(0.28)),
        CustomMultiChildLayout(
          delegate: IncomingLayout(
            safeTop: pad.top,
            introTop: 120.vs,
            minIntroTop: 48.vs,
            introSlack: 16.vs,
            actionsBottom: 80.vs,
          ),
          children: [
            LayoutId(
              id: IncomingLayout.intro,
              child: LayoutBuilder(
                // Laid out at the screen width, then scaled down as a whole
                // if it still does not fit (a long name on a small phone).
                builder: (_, c) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: c.maxWidth,
                    child: const IncomingIntro(),
                  ),
                ),
              ),
            ),
            LayoutId(
              id: IncomingLayout.actions,
              child: const IncomingActions(),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: CallPermissionBar(needsCamera: video),
          ),
        ),
        if (company)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Center(child: IncomingOfficialPill()),
            ),
          ),
      ],
    );
  }
}

/// Video call: the receiver sees their own camera, mirrored, full screen
/// (no remote video yet). Only once the engine is up.
class _OwnPreview extends HookWidget {
  const _OwnPreview();

  @override
  Widget build(BuildContext context) {
    final (ready, key, front) = useMediaSelect(
      (m) => (m.engineReady, m.localViewKey, m.frontCamera),
    );
    final view = callLocalVideo(
      engineReady: ready,
      viewKey: key,
      front: front,
      tag: 'incoming',
    );
    return view ?? const SizedBox.shrink();
  }
}

/// RN geometry where it fits: the intro (avatar block) starts safe top +
/// [introTop], the action area (safety card + buttons) ends [actionsBottom]
/// above the SCREEN bottom (not safe-area aware). RN let them overlap on a
/// small phone (U7); here the intro moves up (down to [minIntroTop] below
/// the safe top, clear of the "App Official" pill), then scales down to end
/// above the action area. As in RN, the action area may cover the empty
/// bottom margin of the intro, up to [introSlack].
class IncomingLayout extends MultiChildLayoutDelegate {
  IncomingLayout({
    required this.safeTop,
    required this.introTop,
    required this.minIntroTop,
    required this.introSlack,
    required this.actionsBottom,
  });

  static const intro = 'intro';
  static const actions = 'actions';

  final double safeTop;
  final double introTop;
  final double minIntroTop;
  final double introSlack;
  final double actionsBottom;

  @override
  void performLayout(Size size) {
    final a = layoutChild(actions, BoxConstraints.tightFor(width: size.width));
    final actionsTop = size.height - actionsBottom - a.height;
    positionChild(actions, Offset(0, actionsTop));

    final introEnd = actionsTop + introSlack;
    final room = math.max(0.0, introEnd - safeTop - minIntroTop);
    final i = layoutChild(
      intro,
      BoxConstraints(maxWidth: size.width, maxHeight: room),
    );
    // As low as RN puts it, never into the action area.
    final gap = (introEnd - safeTop - i.height).clamp(
      minIntroTop,
      math.max(minIntroTop, introTop),
    );
    positionChild(intro, Offset((size.width - i.width) / 2, safeTop + gap));
  }

  @override
  bool shouldRelayout(IncomingLayout old) =>
      safeTop != old.safeTop ||
      introTop != old.introTop ||
      minIntroTop != old.minIntroTop ||
      introSlack != old.introSlack ||
      actionsBottom != old.actionsBottom;
}
