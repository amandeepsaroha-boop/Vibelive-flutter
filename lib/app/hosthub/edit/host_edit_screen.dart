import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_keys.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/profile_models.dart';
import '../../api/hosthub/profile_patch.dart';
import '../../api/paymentscreen/billing_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../component/c_alert.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/keyboard_inset.dart';
import '../../component/pressable.dart';
import '../../component/status_bar_style.dart';
import '../onboarding/helper/draft_controller.dart';
import '../onboarding/helper/host_palette.dart';
import '../onboarding/helper/prefill.dart';
import '../onboarding/helper/submit_plan.dart';
import '../onboarding/helper/validation.dart';
import '../onboarding/steps/availability_step.dart';
import '../onboarding/steps/rates_step.dart';
import '../onboarding/widgets/continue_bar.dart';

enum HostEditSection { schedule, rates }

/// An approved host's "My Schedule" / "Call Rates": the onboarding step on
/// its own, seeded from the saved profile, with a Save button.
class HostEditScreen extends HookWidget {
  const HostEditScreen({super.key, required this.section});
  final HostEditSection section;

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final host = HostProfile.from(session.expert);
    final draft = useMemoized(() {
      final d = HostDraftController('edit', persist: false);
      if (host != null) HostPrefill.hostSettings(d, host);
      return d;
    });
    useEffect(() => draft.dispose, [draft]);
    final pricing = usePricingConfig(context).data ?? PricingConfig.empty;
    final saving = useState(false);
    final update = useUpdateHostProfile(
      alsoInvalidate: const [ClientKeys.profiles],
    );
    final p = HostPalette.of(context);
    final isSchedule = section == HostEditSection.schedule;

    Future<void> save() async {
      final expertId = host?.key ?? '';
      if (expertId.isEmpty || saving.value) return;
      final issue = isSchedule
          ? HostValidation.availability(draft)
          : HostValidation.rates(
              draft,
              pricing.minimumVoiceRate,
              pricing.minimumVideoRate,
            );
      if (issue != null) {
        CToast.show(
          issue.key,
          variables: issue.variables,
          variant: CToastVariant.error,
        );
        return;
      }
      final rates = HostValidation.ratesOf(draft);
      final patch = isSchedule
          ? HostProfilePatch({
              ...HostProfilePatch.schedule(
                vacation: draft.vacation.value,
                callAnyTime: false,
                week: HostSubmitPlan.week(draft),
              ).data,
              'callAnyTime': draft.availableNow.value && !draft.vacation.value,
            })
          : HostProfilePatch.rates(
              voice: rates.voiceCallRate,
              video: rates.videoCallRate,
            );
      saving.value = true;
      try {
        await update.mutateAsync((expertId: expertId, patch: patch));
        CToast.show('hostflow:edit.saved', variant: CToastVariant.success);
        if (context.mounted && context.canPop()) context.pop();
      } on ApiException catch (e) {
        await CAlert.error(e);
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: p.bg,
        resizeToAvoidBottomInset: false,
        body: KeyboardInset(
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.ms, 8.ms, 20.ms, 0),
                  child: Row(
                    children: [
                      Pressable(
                        onPressed: () => context.pop(),
                        semanticLabel: context.t('hostflow:back'),
                        child: Container(
                          width: 40.ms,
                          height: 40.ms,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.tint,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.chevronLeft,
                            size: 22.ms,
                            color: p.text,
                          ),
                        ),
                      ),
                      SizedBox(width: 12.ms),
                      Expanded(
                        child: CText(
                          isSchedule
                              ? 'hostflow:edit.schedule_title'
                              : 'hostflow:edit.rates_title',
                          size: 17,
                          weight: FontWeight.w700,
                          color: p.text,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: isSchedule
                    ? AvailabilityStep(draft: draft)
                    : RatesStep(draft: draft),
              ),
              SafeArea(
                top: false,
                minimum: EdgeInsets.only(bottom: 12.ms),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.ms, 10.ms, 20.ms, 0),
                  child: HostButton(
                    label: 'hostflow:edit.save',
                    arrow: false,
                    loading: saving.value,
                    onPressed: host == null ? null : save,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
