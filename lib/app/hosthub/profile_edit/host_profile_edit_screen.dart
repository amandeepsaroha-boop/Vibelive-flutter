import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_models.dart';
import '../../api/client/client_queries.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/hosthub/onboarding_models.dart';
import '../../api/hosthub/profile_models.dart';
import '../../component/c_alert.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/pressable.dart';
import '../common/host_page.dart';
import '../common/moderation_banners.dart';
import '../onboarding/helper/draft_controller.dart';
import '../onboarding/helper/host_palette.dart';
import '../onboarding/helper/host_steps.dart';
import '../onboarding/helper/prefill.dart';
import '../onboarding/helper/submit_plan.dart';
import '../onboarding/helper/validation.dart';
import '../onboarding/steps/basic_profile_step.dart';
import '../onboarding/steps/bio_step.dart';
import '../onboarding/steps/photos_step.dart';
import '../onboarding/steps/tagline_step.dart';
import '../onboarding/widgets/continue_bar.dart';

/// Professional Details for an existing host (RN ProfessionalDetailsScreen):
/// the onboarding's profile, photos, tagline and bio steps as tabs, seeded
/// from the saved profile, one Save. Changes go through moderation (the
/// banners above say what is still being reviewed).
class HostProfileEditScreen extends HookWidget {
  const HostProfileEditScreen({super.key});

  static const _tabs = [
    (HostStep.basic, 'hostflow:edit.tab_profile'),
    (HostStep.photos, 'hostflow:edit.tab_photos'),
    (HostStep.tagline, 'hostflow:edit.tab_tagline'),
    (HostStep.bio, 'hostflow:edit.tab_bio'),
  ];

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final hostQ = useHostProfile(context);
    final host = hostQ.data ?? HostProfile.from(session.expert);
    final me = useMyProfile(context).data;
    final draft = useMemoized(
      () => HostDraftController('edit', persist: false),
    );
    useEffect(() => draft.dispose, [draft]);
    final ready = useState(false);
    useEffect(() {
      if (!ready.value && host != null) {
        HostPrefill.apply(
          draft,
          me ?? UserWithExpert(user: session.user ?? const {}),
          host: host,
        );
        ready.value = true;
      }
      return null;
    }, [host?.key, me]);
    final tab = useState(0);
    final saving = useState(false);
    final save = useSaveHostProfileEdit();
    final p = HostPalette.of(context);

    Future<void> submit() async {
      final user = session.userDocumentId;
      if (host == null || user == null || saving.value) return;
      for (final (i, (step, _)) in _tabs.indexed) {
        final issue = HostValidation.check(step, draft);
        if (issue != null) {
          tab.value = i;
          draft.notice.value = issue;
          return;
        }
      }
      saving.value = true;
      try {
        final free = await ensureHostHandleCheck(
          draft.handle.text,
          ownExpertId: host.key,
        );
        if (!free) {
          tab.value = 0;
          draft.notice.value = (
            key: 'hostflow:errors.handle_taken',
            variables: null,
          );
          return;
        }
        await save.mutateAsync(
          HostProfileEditInput(
            userDocumentId: user,
            expertId: host.key,
            handler: draft.handle.text.trim(),
            tagline: draft.tagline.text.trim(),
            gender: draft.gender.value,
            description: draft.bio.text.trim(),
            languages: draft.languages.value,
            photoMediaIds: [
              for (final ph in draft.photos.value)
                if (ph.mediaId != null) ph.mediaId!,
            ],
            userPatch: me == null
                ? const {}
                : HostSubmitPlan.userPatch(draft, me),
          ),
        );
        CToast.show('hostflow:edit.saved', variant: CToastVariant.success);
        if (context.mounted) HostPage.leave(context);
      } on ApiException catch (e) {
        await CAlert.error(e, title: 'hostflow:hub.pro_details');
      } finally {
        if (context.mounted) saving.value = false;
      }
    }

    if (host == null || !ready.value) {
      return HostPage(
        title: 'hostflow:hub.pro_details',
        body: hostQ.isLoading || host != null
            ? const HostPageSkeleton()
            : const CStateView(title: 'hostflow:hub.no_profile'),
      );
    }

    return HostPage(
      title: 'hostflow:hub.pro_details',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder(
            valueListenable: draft.notice,
            builder: (_, issue, _) => issue == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.only(bottom: 10.ms),
                    child: CText(
                      issue.key,
                      variables: issue.variables,
                      size: 13,
                      weight: FontWeight.w600,
                      color: p.danger,
                      align: TextAlign.center,
                    ),
                  ),
          ),
          HostButton(
            key: const ValueKey('host-edit-save'),
            label: 'hostflow:edit.save',
            arrow: false,
            loading: saving.value,
            onPressed: submit,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20.ms, 6.ms, 20.ms, 0),
            child: HostModerationBanners(host: host),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.ms, vertical: 6.ms),
            child: _Tabs(
              labels: [for (final (_, l) in _tabs) l],
              selected: tab.value,
              onSelect: (i) => tab.value = i,
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(tab.value),
                child: switch (_tabs[tab.value].$1) {
                  HostStep.basic => BasicProfileStep(draft: draft),
                  HostStep.photos => PhotosStep(draft: draft),
                  HostStep.tagline => TaglineStep(draft: draft),
                  _ => BioStep(draft: draft),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat segmented tabs.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      height: 44.ms,
      padding: EdgeInsets.all(3.ms),
      decoration: BoxDecoration(
        color: p.neutral,
        borderRadius: BorderRadius.circular(14.ms),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: Pressable(
                onPressed: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? p.accent : null,
                    borderRadius: BorderRadius.circular(11.ms),
                  ),
                  child: CText(
                    label,
                    size: 13,
                    weight: FontWeight.w700,
                    color: i == selected ? p.onAccent : p.muted,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
