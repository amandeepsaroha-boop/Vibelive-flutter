import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/host_events.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/eligibility.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/profile_models.dart';
import '../../api/hosthub/verification_models.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../common/host_page.dart';
import '../onboarding/helper/host_palette.dart';
import '../onboarding/widgets/continue_bar.dart';

/// Verification Badge (RN VerificationBadgeScreen), or with [review] the
/// RN VerificationStatusScreen: where the host stands, the checklist, and
/// the next action (pay the fee, finish the form, or done).
class HostBadgeScreen extends HookWidget {
  const HostBadgeScreen({super.key, this.review = false});

  final bool review;

  /// RN: only identity is checked (the other fields are commented out).
  static const checklist = ['Identity_Verified'];

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final allowed = HostEligibility.canApplyForBadge(session.expert);
    final expertId = HostProfile.from(session.expert)?.key;
    final latest = useLatestVerification(
      context,
      expertId: expertId,
      enabled: allowed,
    );
    final p = HostPalette.of(context);
    // Analytics: the step last reported as viewed.
    final viewed = useRef<String?>(null);
    final title = review
        ? 'hostflow:badge.status_title'
        : 'hostflow:badge.title';

    if (!allowed) return HostBadgeLocked(title: title);
    if (latest.data == null && latest.isLoading) {
      return HostPage(title: title, body: const HostPageSkeleton());
    }
    if (latest.data == null && latest.isError) {
      return HostPage(
        title: title,
        body: CStateView.error(context, latest.error!, onRetry: latest.refetch),
      );
    }
    final record = latest.data;
    final step = VerificationRecord.nextStepOf(record?.raw);
    if (viewed.value != step.name) {
      viewed.value = step.name;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => HostEvents.badgeStatusViewed(step: step.name, review: review),
      );
    }

    final card = review
        ? switch (step) {
            VerificationStep.success => const HostToneCard(
              tone: HostTone.success,
              icon: LucideIcons.badgeCheck,
              title: 'hostflow:badge.approved_title',
              message: 'hostflow:badge.approved_body',
            ),
            VerificationStep.review => const HostToneCard(
              tone: HostTone.warning,
              icon: LucideIcons.clock3,
              title: 'hostflow:badge.review_title',
              message: 'hostflow:badge.review_body',
            ),
            _ => const HostToneCard(
              tone: HostTone.danger,
              icon: LucideIcons.circleAlert,
              title: 'hostflow:badge.incomplete_title',
              message: 'hostflow:badge.incomplete_body',
            ),
          }
        : switch (step) {
            VerificationStep.success => const HostToneCard(
              tone: HostTone.success,
              icon: LucideIcons.badgeCheck,
              title: 'hostflow:badge.active_title',
              message: 'hostflow:badge.active_body',
            ),
            VerificationStep.review => const HostToneCard(
              tone: HostTone.warning,
              icon: LucideIcons.clock3,
              title: 'hostflow:badge.under_review_title',
              message: 'hostflow:badge.under_review_body',
            ),
            VerificationStep.form => const HostToneCard(
              tone: HostTone.info,
              icon: LucideIcons.circleCheck,
              title: 'hostflow:badge.paid_title',
              message: 'hostflow:badge.paid_body',
            ),
            VerificationStep.fee => const HostToneCard(
              tone: HostTone.warning,
              icon: LucideIcons.wallet,
              title: 'hostflow:badge.fee_pending_title',
              message: 'hostflow:badge.fee_pending_body',
            ),
          };

    void primary() {
      HostEvents.badgePrimaryTapped(step: step.name, review: review);
      if (review) {
        context.pushReplacement(
          step == VerificationStep.fee || step == VerificationStep.form
              ? AppRoutes.verificationBadgeForm
              : AppRoutes.verificationBadge,
        );
        return;
      }
      switch (step) {
        case VerificationStep.fee:
          context.push(AppRoutes.verificationBadgeFee);
        case VerificationStep.form:
          context.push(AppRoutes.verificationBadgeForm);
        case _:
          context.go('${AppRoutes.home}?tab=me');
      }
    }

    final label = review
        ? (step == VerificationStep.fee || step == VerificationStep.form
              ? 'hostflow:badge.complete_form'
              : 'hostflow:badge.back_to_badge')
        : switch (step) {
            VerificationStep.fee => 'hostflow:badge.pay_fee',
            VerificationStep.form => 'hostflow:badge.complete_form',
            _ => 'hostflow:badge.go_back',
          };

    return HostPage(
      title: title,
      bottom: HostButton(label: label, arrow: false, onPressed: primary),
      body: RefreshIndicator(
        onRefresh: () async => latest.refetch(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 24.ms),
          children: [
            card,
            SizedBox(height: 18.ms),
            CText(
              'hostflow:badge.checklist',
              size: 13,
              weight: FontWeight.w700,
              color: p.muted,
            ),
            SizedBox(height: 8.ms),
            for (final field in checklist)
              _CheckRow(
                label: 'hostflow:badge.field.$field',
                ok: HostFlag.isTruthy(record?.raw[field]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Not approved yet: RN sent the host to Approval Status.
class HostBadgeLocked extends StatefulWidget {
  const HostBadgeLocked({super.key, required this.title});
  final String title;

  @override
  State<HostBadgeLocked> createState() => _HostBadgeLockedState();
}

class _HostBadgeLockedState extends State<HostBadgeLocked> {
  String get title => widget.title;

  @override
  void initState() {
    super.initState();
    HostEvents.badgeLockedViewed(screen: title.split('.').last);
  }

  @override
  Widget build(BuildContext context) => HostPage(
    title: title,
    bottom: HostButton(
      label: 'hostflow:badge.view_approval',
      arrow: false,
      onPressed: () => context.pushReplacement(AppRoutes.approval),
    ),
    body: ListView(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 24.ms),
      children: const [
        HostToneCard(
          tone: HostTone.warning,
          icon: LucideIcons.lock,
          title: 'hostflow:badge.locked_title',
          message: HostEligibility.approvalRequiredKey,
        ),
      ],
    ),
  );
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.ok});
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      height: 54.ms,
      padding: EdgeInsets.symmetric(horizontal: 14.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: CText(
              label,
              size: 15,
              weight: FontWeight.w600,
              color: p.text,
            ),
          ),
          CText(
            ok ? 'hostflow:badge.verified' : 'hostflow:badge.pending',
            size: 12,
            weight: FontWeight.w800,
            color: ok ? p.success : p.warning,
          ),
        ],
      ),
    );
  }
}
