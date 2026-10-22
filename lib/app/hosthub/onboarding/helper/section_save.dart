import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_store.dart';
import '../../../api/authscreen/interests_queries.dart';
import '../../../api/client/client_keys.dart';
import '../../../api/client/client_models.dart';
import '../../../api/hosthub/expertise_models.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/onboarding_models.dart';
import '../../../api/hosthub/profile_patch.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_toast.dart';
import 'draft_controller.dart';
import 'host_steps.dart';
import 'submit_plan.dart';
import 'topic_catalog.dart';
import 'validation.dart';

/// Steps an existing host can save on their own from the Host Hub.
const hostSavableSteps = {
  HostStep.basic,
  HostStep.photos,
  HostStep.tagline,
  HostStep.bio,
  HostStep.interests,
  HostStep.rates,
  HostStep.availability,
};

/// "Save changes" of an existing host's step: only that section, with the
/// update calls the Host Hub always used (profile edit with moderation and
/// `language {set}`, expertise, rates, schedule / vacation). No approval
/// request is filed. True when saved.
Future<bool> Function(HostStep step) useHostSectionSave(
  HostDraftController draft, {
  required UserWithExpert? me,
  required (double, double) Function() rateFloors,
}) {
  final profile = useSaveHostProfileEdit();
  final expertise = useSaveMyExpertise();
  final update = useUpdateHostProfile(
    alsoInvalidate: const [ClientKeys.profiles],
  );

  Future<bool> save(HostStep step) async {
    final session = SessionStore.instance.value;
    final expertId = draft.expertId;
    final user = session.userDocumentId;
    if (expertId == null || user == null) return false;
    const profileSteps = [
      HostStep.basic,
      HostStep.photos,
      HostStep.tagline,
      HostStep.bio,
    ];
    final (voice, video) = rateFloors();
    // One profile save sends all four profile steps: check them all.
    for (final s in profileSteps.contains(step) ? profileSteps : [step]) {
      final issue = HostValidation.check(
        s,
        draft,
        minVoiceRate: voice,
        minVideoRate: video,
      );
      if (issue != null) {
        draft.notice.value = issue;
        return false;
      }
    }
    try {
      switch (step) {
        case HostStep.interests:
          final form = await ensureInterestForm();
          final saved = (await ensureMyExpertise()).selections;
          final all = [for (final q in form.questions) q.toJson()];
          final question = HostTopicCatalog.question(form);
          final selections = ExpertiseQuestions.draft(all, saved);
          if (question != null) {
            selections[question.key] = [
              for (final t in draft.topics.value) t.value,
            ];
          }
          await expertise.mutateAsync((
            selections: selections,
            source: 'settings',
          ));
        case HostStep.rates:
          final rates = HostValidation.ratesOf(draft);
          await update.mutateAsync((
            expertId: expertId,
            patch: HostProfilePatch.rates(
              voice: rates.voiceCallRate,
              video: rates.videoCallRate,
            ),
          ));
        case HostStep.availability:
          final vacation = draft.vacation.value;
          await update.mutateAsync((
            expertId: expertId,
            patch: HostProfilePatch({
              ...HostProfilePatch.schedule(
                vacation: vacation,
                callAnyTime: false,
                week: HostSubmitPlan.week(draft),
              ).data,
              'callAnyTime': draft.availableNow.value && !vacation,
            }),
          ));
        case _:
          final free = await ensureHostHandleCheck(
            draft.handle.text,
            ownExpertId: expertId,
          );
          if (!free) {
            draft.notice.value = (
              key: 'hostflow:errors.handle_taken',
              variables: null,
            );
            return false;
          }
          await profile.mutateAsync(
            HostProfileEditInput(
              userDocumentId: user,
              expertId: expertId,
              handler: draft.handle.text.trim(),
              tagline: draft.tagline.text.trim(),
              gender: draft.gender.value,
              description: draft.bio.text.trim(),
              languages: draft.languages.value,
              photoMediaIds: [
                for (final p in draft.photos.value)
                  if (p.mediaId != null) p.mediaId!,
              ],
              userPatch: me == null
                  ? const {}
                  : HostSubmitPlan.userPatch(draft, me),
            ),
          );
      }
      CToast.show('hostflow:edit.saved', variant: CToastVariant.success);
      return true;
    } on ApiException catch (e) {
      await CAlert.error(e);
      return false;
    }
  }

  return save;
}
