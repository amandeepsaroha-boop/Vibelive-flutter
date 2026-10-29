import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/call_ui_events.dart';
import '../../../core/analytics/screen_tracker.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/callscreen/call_errors.dart';
import '../../api/callscreen/call_queries.dart';
import '../../api/callscreen/review_api.dart';
import '../../api/client/client_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_button.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/keyboard_inset.dart';
import 'helper/history_entry.dart';
import 'helper/history_errors.dart';
import 'history_note_field.dart';

/// "Rate this Call" (RN explore review modal). Closes only through X, Skip or
/// a successful submit; true when a review was saved. Skip / Submit are
/// pinned under the scrolling part, so they stay above the keyboard with the
/// comment.
Future<bool> showReviewSheet(BuildContext context, HistoryEntry entry) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.transparent,
      barrierColor: AppColors.blackA(0.65),
      routeSettings: ScreenTracker.sheet('call_review_sheet'),
      builder: (_) => KeyboardInset(child: _ReviewSheet(entry: entry)),
    ) ??
    false;

class _ReviewSheet extends HookWidget {
  const _ReviewSheet({required this.entry});
  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final rating = useState(0);
    final comment = useTextEditingController();
    final hasText = useListenableSelector(
      comment,
      () => comment.text.trim().isNotEmpty,
    );
    final busy = useState(false);
    final submit = useSubmitReview();
    final canSubmit = rating.value > 0 || hasText;
    final subtle = dark ? AppColors.whiteA(0.45) : AppColors.blackA(0.42);

    void skip() {
      CallUiEvents.reviewSkipped(rating: rating.value, hasComment: hasText);
      Navigator.of(context).pop(false);
    }

    void track(bool success, {String? hostId, String? error}) =>
        CallUiEvents.reviewSubmitted(
          success: success,
          rating: rating.value,
          hasComment: hasText,
          hostId: hostId,
          callId: entry.item.call.id?.toString(),
          error: error,
        );

    Future<void> send() async {
      final me = SessionStore.instance.value.userDocumentId;
      if (!canSubmit || busy.value || me == null) return;
      busy.value = true;
      try {
        final expertId = await _expertIdOf(entry.counterpartId);
        // RN: "Unable to resolve Host Profile." and nothing is posted.
        if (expertId == null) {
          track(false, error: 'expert_unresolved');
          unawaited(
            CAlert.show(
              title: HistoryErrors.title,
              message: 'call:history.review.expert_unresolved',
              variant: CAlertVariant.error,
            ),
          );
          return;
        }
        await submit.mutateAsync(
          ReviewInput(
            expertId: expertId,
            userId: me,
            rating: rating.value,
            comments: comment.text,
            // RN posts the numeric call id (`call: c.id`).
            callId: entry.item.call.id,
          ),
        );
        track(true, hostId: expertId);
        if (context.mounted) Navigator.of(context).pop(true);
      } on ApiException catch (e) {
        track(false, error: Analytics.errorCode(e));
        unawaited(
          CAlert.error(
            HistoryErrors.relabel(e, CallErrorKeys.reviewFailed),
            title: HistoryErrors.title,
          ),
        );
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return PopScope(
      canPop: false,
      child: Container(
        decoration: BoxDecoration(
          color: c.modalCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.ms)),
          border: Border.all(color: c.modalBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20.ms, 20.ms, 20.ms, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // RN: "with Unknown" when the name is missing.
                    _Header(
                      name: entry.name ?? context.t('call:history.unknown'),
                      subtle: subtle,
                      onClose: skip,
                    ),
                    SizedBox(height: 18.ms),
                    _Stars(
                      value: rating.value,
                      onChanged: (v) {
                        rating.value = v;
                        CallUiEvents.reviewRatingSelected(rating: v);
                      },
                    ),
                    SizedBox(height: 20.ms),
                    if (!canSubmit) ...[
                      CText(
                        'call:history.review.hint',
                        size: 11,
                        weight: FontWeight.w700,
                        color: subtle,
                        align: TextAlign.center,
                      ),
                      SizedBox(height: 14.ms),
                    ],
                    HistoryNoteField(
                      controller: comment,
                      placeholder: 'call:history.review.placeholder',
                      minLines: 4,
                      radius: 16,
                      highlighted: hasText,
                    ),
                  ],
                ),
              ),
            ),
            _Footer(
              child: Row(
                children: [
                  Expanded(
                    child: CButton(
                      title: 'call:history.review.skip',
                      variant: CButtonVariant.outline,
                      showArrow: false,
                      height: 50.ms,
                      titleSize: 13,
                      onPressed: skip,
                    ),
                  ),
                  SizedBox(width: 10.ms),
                  Expanded(
                    flex: 2,
                    child: CButton(
                      title: 'call:history.review.submit',
                      showArrow: false,
                      height: 50.ms,
                      titleSize: 13,
                      disabled: !canSubmit,
                      loading: busy.value,
                      onPressed: send,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The host's expert-profile id, which the review is filed under (RN
  /// `getExpertProfileId`). Unresolved → null.
  static Future<String?> _expertIdOf(String? userId) async {
    if (userId == null) return null;
    try {
      return (await ensureUserWithExpert(userId)).expertId;
    } on ApiException {
      return null;
    }
  }
}

/// The buttons' row: RN's 36 pt bottom, more when the home indicator needs
/// it. On a device the bottom padding drops to 0 while the keyboard is up;
/// only this row reads it.
class _Footer extends StatelessWidget {
  const _Footer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20.ms,
        16.ms,
        20.ms,
        math.max(36.ms, inset + 16.ms),
      ),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.subtle,
    required this.onClose,
  });
  final String name;
  final Color subtle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CText(
                'call:history.review.title',
                size: 20,
                weight: FontWeight.w900,
                letterSpacing: -0.4,
                color: c.modalText,
              ),
              SizedBox(height: 2.ms),
              CText(
                'call:history.review.with',
                variables: {'name': name},
                size: 11,
                weight: FontWeight.w700,
                color: subtle,
                maxLines: 1,
              ),
            ],
          ),
        ),
        Pressable(
          onPressed: onClose,
          semanticLabel: context.t('actions.close'),
          child: Container(
            width: 36.ms,
            height: 36.ms,
            decoration: BoxDecoration(
              color: c.isDark ? AppColors.whiteA(0.07) : AppColors.blackA(0.06),
              borderRadius: BorderRadius.circular(12.ms),
            ),
            child: Icon(LucideIcons.x, size: 18.ms, color: c.modalText),
          ),
        ),
      ],
    );
  }
}

/// Five tappable stars (RN size 36, gap 10).
class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final off = c.isDark ? AppColors.whiteA(0.2) : AppColors.blackA(0.15);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var n = 1; n <= 5; n++)
          Pressable(
            onPressed: () => onChanged(n),
            semanticLabel: context.t(
              'call:history.review.star',
              variables: {'value': n},
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 5.ms),
              child: Icon(
                n <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 40.ms,
                color: n <= value ? c.accent : off,
              ),
            ),
          ),
      ],
    );
  }
}
