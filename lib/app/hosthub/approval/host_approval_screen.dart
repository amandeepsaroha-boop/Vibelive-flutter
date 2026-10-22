import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_keys.dart';
import '../../api/hosthub/approval_models.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/profile_models.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../common/host_page.dart';
import '../onboarding/helper/host_palette.dart';
import '../onboarding/widgets/continue_bar.dart';
import '../onboarding/widgets/step_body.dart';

/// Approval Status (RN ApprovalScreen): status, the sections still missing,
/// then one action — send the request (again after a rejection), or go live
/// once approved. While a request is under review there is no button.
class HostApprovalScreen extends HookWidget {
  const HostApprovalScreen({super.key});

  /// RN's backstop for a request the server read cannot see yet.
  static String sentKey(String expertId) => '@approval_request_sent:$expertId';

  static const sectionRoutes = {
    HostProfileSection.professional: AppRoutes.professionalDetails,
    HostProfileSection.expertise: AppRoutes.expertise,
    HostProfileSection.schedule: AppRoutes.schedule,
    HostProfileSection.rates: AppRoutes.callRates,
  };

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final hostQ = useHostProfile(context);
    final host = hostQ.data ?? HostProfile.from(session.expert);
    final completion = useHostCompletion(context, host);
    final latest = useLatestApproval(context, expertId: host?.key);
    final busy = useState(false);
    final send = useRequestApproval(
      alsoInvalidate: const [ClientKeys.profiles],
    );
    final goLive = useGoLive(alsoInvalidate: const [ClientKeys.profiles]);
    final p = HostPalette.of(context);

    if (host == null) {
      return HostPage(
        title: 'hostflow:approval.title',
        body: hostQ.isLoading
            ? const HostPageSkeleton()
            : const CStateView(title: 'hostflow:hub.no_profile'),
      );
    }
    final loading =
        (latest.data == null && latest.isLoading) ||
        (completion.data == null && completion.isLoading);
    final failed = latest.isError && latest.data == null;
    var status = ApprovalRecord.effective(host, latest.data);
    if (status == null && AppPrefs.getString(sentKey(host.key)) != null) {
      status = ApprovalStatus.pending;
    }
    final missing = completion.data?.missing ?? const <HostProfileSection>[];

    Future<void> request() async {
      if (missing.isNotEmpty) {
        await CAlert.show(
          title: 'hostflow:approval.title',
          message: 'hostflow:approval.complete_first',
          variant: CAlertVariant.warning,
        );
        return;
      }
      busy.value = true;
      try {
        final result = await send.mutateAsync(host.key);
        await AppPrefs.setString(
          sentKey(host.key),
          DateTime.now().toIso8601String(),
        );
        if (result == ApprovalStatus.pending) {
          await CAlert.show(
            title: 'hostflow:approval.sent_title',
            message: 'hostflow:approval.sent_body',
            variant: CAlertVariant.success,
          );
        }
      } on ApiException catch (e) {
        await CAlert.error(e, title: 'hostflow:approval.title');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    Future<void> live() async {
      busy.value = true;
      try {
        final user = session.user;
        await goLive.mutateAsync((
          expertId: host.key,
          name: user?['name']?.toString(),
          email: user?['email']?.toString(),
        ));
        await CAlert.show(
          title: 'hostflow:approval.live_title',
          message: 'hostflow:approval.live_body',
          variant: CAlertVariant.success,
        );
        if (context.mounted) context.go('${AppRoutes.home}?tab=me');
      } on ApiException catch (e) {
        await CAlert.error(e, title: 'hostflow:approval.go_live');
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    final Widget? action = loading
        ? null
        : failed
        ? HostButton(
            label: 'hostflow:hub.retry',
            arrow: false,
            onPressed: latest.refetch,
          )
        : switch (status) {
            ApprovalStatus.pending => null,
            ApprovalStatus.approved => HostButton(
              label: 'hostflow:approval.go_live',
              loading: busy.value,
              onPressed: live,
            ),
            ApprovalStatus.rejected => HostButton(
              label: 'hostflow:approval.send_again',
              loading: busy.value,
              onPressed: request,
            ),
            null => HostButton(
              label: 'hostflow:approval.send',
              loading: busy.value,
              onPressed: request,
            ),
          };

    return HostPage(
      title: 'hostflow:approval.title',
      bottom: action,
      body: loading
          ? const HostPageSkeleton()
          : ListView(
              padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 24.ms),
              children: [
                const HostTitle('hostflow:approval.heading'),
                SizedBox(height: 6.ms),
                CText(
                  'hostflow:approval.subtitle',
                  size: 15,
                  height: 21,
                  color: p.muted,
                ),
                SizedBox(height: 18.ms),
                if (status != null) ...[
                  _statusCard(status),
                  SizedBox(height: 12.ms),
                ],
                if (missing.isNotEmpty)
                  _MissingCard(missing: missing)
                else
                  const HostToneCard(
                    tone: HostTone.info,
                    icon: LucideIcons.listChecks,
                    title: 'hostflow:approval.how_title',
                    message: 'hostflow:approval.how_body',
                  ),
                SizedBox(height: 16.ms),
                Center(
                  child: Pressable(
                    onPressed: () =>
                        context.go('${AppRoutes.home}?tab=discover'),
                    hitPadding: EdgeInsets.all(8.ms),
                    child: CText(
                      'hostflow:approval.explore',
                      size: 14,
                      weight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  static Widget _statusCard(ApprovalStatus s) => switch (s) {
    ApprovalStatus.approved => const HostToneCard(
      tone: HostTone.success,
      icon: LucideIcons.circleCheck,
      title: 'hostflow:approval.approved_title',
      message: 'hostflow:approval.approved_body',
    ),
    ApprovalStatus.pending => const HostToneCard(
      tone: HostTone.warning,
      icon: LucideIcons.clock3,
      title: 'hostflow:approval.pending_title',
      message: 'hostflow:approval.pending_body',
    ),
    ApprovalStatus.rejected => const HostToneCard(
      tone: HostTone.danger,
      icon: LucideIcons.triangleAlert,
      title: 'hostflow:approval.rejected_title',
      message: 'hostflow:approval.rejected_body',
    ),
  };
}

/// "Complete required sections": each one opens its screen.
class _MissingCard extends StatelessWidget {
  const _MissingCard({required this.missing});
  final List<HostProfileSection> missing;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: p.warningTint,
        borderRadius: BorderRadius.circular(16.ms),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CText(
            'hostflow:approval.missing_title',
            size: 15,
            weight: FontWeight.w800,
            color: p.warning,
          ),
          for (final s in missing)
            Pressable(
              onPressed: () =>
                  context.push(HostApprovalScreen.sectionRoutes[s]!),
              child: Padding(
                padding: EdgeInsets.only(top: 10.ms),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.circleDashed,
                      size: 16.ms,
                      color: p.warning,
                    ),
                    SizedBox(width: 8.ms),
                    Expanded(
                      child: CText(
                        s.i18nKey,
                        size: 14,
                        weight: FontWeight.w600,
                        color: p.text,
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, size: 16.ms, color: p.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
