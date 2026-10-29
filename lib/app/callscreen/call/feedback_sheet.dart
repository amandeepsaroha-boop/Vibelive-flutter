import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/analytics/screen_tracker.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_alert.dart';
import '../../component/c_text.dart';
import '../../component/keyboard_inset.dart';
import '../../component/pressable.dart';
import '../helper/call_actions.dart';
import 'feedback_parts.dart';
import 'helper/call_guard.dart';
import 'helper/call_motion.dart';
import 'helper/call_track.dart';

/// How the rating sheet closed. Every way out leaves the call screen.
enum FeedbackExit { submitted, skipped, blocked }

/// RN `FeedBackModal` (caller, after a connected call): stars, optional
/// comment, Submit / Skip / Block. The backdrop fades in (250 ms), the sheet
/// springs up; closing is instant (RN unmounted it). The sheet lifts above
/// the keyboard and its upper part scrolls, so Submit stays visible on a
/// small phone. Null when something else removed it.
Future<FeedbackExit?> showFeedbackSheet(
  BuildContext context, {
  String? name,
  bool canBlock = true,
}) => showGeneralDialog<FeedbackExit>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: false,
  barrierColor: AppColors.transparent,
  transitionDuration: CallMotion.sheetTime,
  routeSettings: ScreenTracker.sheet('call_feedback_sheet'),
  pageBuilder: (_, anim, _) =>
      _FeedbackRoute(animation: anim, name: name, canBlock: canBlock),
);

class _FeedbackRoute extends HookWidget {
  const _FeedbackRoute({
    required this.animation,
    required this.name,
    required this.canBlock,
  });

  final Animation<double> animation;
  final String? name;
  final bool canBlock;

  static const _backdropFade = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    // Submit / Block in flight (which one): Skip, back and the backdrop do
    // nothing meanwhile (U8).
    final busy = useValueNotifier<FeedbackExit?>(null);

    void close(FeedbackExit how) {
      if (!context.mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route, how);
      }
    }

    void skip() {
      if (busy.value != null) return;
      CallUiEvents.feedbackSkipped(currentCallInfo(), rating: 0);
      close(FeedbackExit.skipped);
    }

    final fade = animation.drive(
      CurveTween(
        curve: Interval(
          0,
          _backdropFade.inMicroseconds / CallMotion.sheetTime.inMicroseconds,
          curve: Curves.easeInOut,
        ),
      ),
    );
    final height = MediaQuery.sizeOf(context).height;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) skip();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: skip,
              child: FadeTransition(
                opacity: fade,
                child: ColoredBox(color: AppColors.blackA(0.85)),
              ),
            ),
          ),
          Positioned.fill(
            child: KeyboardInset(
              child: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (_, sheet) {
                      final t = CallMotion.sheetCurve.transform(
                        animation.value,
                      );
                      return Transform.translate(
                        offset: Offset(0, height * (1 - t)),
                        child: sheet,
                      );
                    },
                    child: _FeedbackSheet(
                      name: name,
                      canBlock: canBlock,
                      busy: busy,
                      onClose: close,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackSheet extends HookWidget {
  const _FeedbackSheet({
    required this.name,
    required this.canBlock,
    required this.busy,
    required this.onClose,
  });

  final String? name;
  final bool canBlock;

  /// Owned by the route (it also gates the backdrop and back).
  final ValueNotifier<FeedbackExit?> busy;
  final void Function(FeedbackExit how) onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rating = useState(0);
    final comment = useTextEditingController();
    final inFlight = useInFlight();
    final working = useValueListenable(busy);

    // [busy] belongs to the route: written only while it is still up.
    void setBusy(FeedbackExit? v) {
      if (context.mounted) busy.value = v;
    }

    Future<void> submit() => inFlight.run(() async {
      if (rating.value == 0) return;
      // Busy until the sheet is gone (submitFeedback never throws).
      setBusy(FeedbackExit.submitted);
      await CallActions.submitFeedback(
        rating: rating.value,
        comments: comment.text.trim(),
      );
      onClose(FeedbackExit.submitted);
    });

    Future<void> block() => inFlight.run(() async {
      final call = currentCallInfo();
      final ok = await CAlert.show(
        context: context,
        title: 'call:feedback.block_title',
        message: 'call:feedback.block_message',
        variables: {'name': name ?? context.t('call:feedback.block_fallback')},
        primaryLabel: 'call:incoming.block',
        secondaryLabel: 'actions.cancel',
        variant: CAlertVariant.error,
      );
      CallUiEvents.safetyConfirm(
        action: 'block',
        source: 'after_call',
        confirmed: ok == true,
        call: call,
      );
      if (ok != true || !context.mounted) return;
      setBusy(FeedbackExit.blocked);
      final blocked = await CallActions.blockAfterCall();
      CallUiEvents.safetyAction(
        action: 'block',
        source: 'after_call',
        outcome: blocked ? 'done' : 'failed',
        call: call,
      );
      if (!context.mounted) return;
      if (!blocked) {
        await CAlert.show(
          context: context,
          title: 'call:feedback.block_failed_title',
          message: 'call:feedback.block_failed',
          variant: CAlertVariant.error,
        );
        setBusy(null); // still on the sheet: try again or skip
        return;
      }
      await CAlert.show(
        context: context,
        title: 'call:feedback.blocked_title',
        message: 'call:feedback.blocked',
        variant: CAlertVariant.success,
      );
      // Decision 4: RN left the user on the ended summary; leave instead.
      onClose(FeedbackExit.blocked);
    });

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(36.ms)),
          border: Border(
            top: BorderSide(color: c.accentA(0.15), width: 1.5),
            left: BorderSide(color: c.accentA(0.15), width: 1.5),
            right: BorderSide(color: c.accentA(0.15), width: 1.5),
          ),
          boxShadow: [
            BoxShadow(
              color: c.accentA(0.12),
              blurRadius: 25,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.sw, 12.vs, 24.sw, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FeedbackHead(name: name),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 28.vs),
                      child: FeedbackStars(
                        value: rating.value,
                        onChanged: (v) {
                          rating.value = v;
                          CallUiEvents.feedbackRatingSelected(
                            currentCallInfo(),
                            rating: v,
                          );
                        },
                      ),
                    ),
                    FeedbackComment(
                      controller: comment,
                      formatters: [LengthLimitingTextInputFormatter(300)],
                    ),
                    SizedBox(height: 24.vs),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24.sw, 0, 24.sw, 36.vs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FeedbackSubmit(
                    enabled:
                        rating.value > 0 && working != FeedbackExit.blocked,
                    loading: working == FeedbackExit.submitted,
                    onPressed: submit,
                  ),
                  SizedBox(height: 12.vs),
                  Pressable(
                    onPressed: working == null
                        ? () {
                            CallUiEvents.feedbackSkipped(
                              currentCallInfo(),
                              rating: rating.value,
                            );
                            onClose(FeedbackExit.skipped);
                          }
                        : null,
                    activeOpacity: 0.7,
                    child: SizedBox(
                      width: double.infinity,
                      height: 48.vs,
                      child: Center(
                        child: CText(
                          'call:feedback.skip',
                          color: AppColors.whiteA(0.5),
                          size: 13,
                          weight: FontWeight.w700,
                          letterSpacing: 0.5,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                  if (canBlock) ...[
                    SizedBox(height: 12.vs),
                    Pressable(
                      onPressed: working == null ? block : null,
                      activeOpacity: 0.7,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.vs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.userX,
                              size: 14.ms,
                              color: StatusColors.dangerRed,
                            ),
                            const SizedBox(width: 6),
                            const Flexible(
                              child: CText(
                                'call:feedback.block',
                                color: StatusColors.dangerRed,
                                size: 12,
                                weight: FontWeight.w700,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
