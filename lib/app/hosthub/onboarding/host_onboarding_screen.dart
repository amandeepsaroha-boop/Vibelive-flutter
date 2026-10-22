import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../api/authscreen/interests_queries.dart';
import '../../api/client/client_models.dart';
import '../../api/client/client_queries.dart';
import '../../api/hosthub/hosthub_queries.dart';
import '../../api/paymentscreen/billing_models.dart';
import '../../api/paymentscreen/payment_queries.dart';
import '../../component/c_alert.dart';
import '../../component/keyboard_inset.dart';
import '../../component/status_bar_style.dart';
import 'helper/draft_controller.dart';
import 'helper/flow_controller.dart';
import 'helper/host_palette.dart';
import 'helper/host_steps.dart';
import 'helper/intro_image.dart';
import 'helper/prefill.dart';
import 'helper/submit_plan.dart';
import 'helper/topic_catalog.dart';
import 'steps/availability_step.dart';
import 'steps/basic_profile_step.dart';
import 'steps/bio_step.dart';
import 'steps/interests_step.dart';
import 'steps/intro_step.dart';
import 'steps/photos_step.dart';
import 'steps/rates_step.dart';
import 'steps/guidelines_step.dart';
import 'steps/preview_step.dart';
import 'steps/submitted_step.dart';
import 'steps/tagline_step.dart';
import 'widgets/continue_bar.dart';
import 'widgets/progress_header.dart';

/// "Become a Host": intro, eight form steps, success. The draft is saved
/// per account as the user goes, so the flow resumes where it was left.
/// Nothing is created on the backend before "Submit for review": a host
/// profile turns the account into a host everywhere in the app.
class HostOnboardingScreen extends HookWidget {
  const HostOnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = useMemoized(() => SessionStore.instance.value);
    final userKey = session.userDocumentId ?? '${session.userId ?? ''}';
    final draft = useMemoized(() => HostDraftController.load(userKey));
    useEffect(() => draft.dispose, [draft]);
    // Entry points precache it already; this covers deep links.
    useEffect(() {
      // After the first frame: precaching reads inherited widgets.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) HostIntroImage.precache(context).ignore();
      });
      return null;
    }, const []);
    final me = _usePrefill(context, draft, session);

    final submit = useSubmitHostOnboarding();
    final pricing = usePricingConfig(context).data ?? PricingConfig.empty;
    // Only intro <-> flow rebuilds this widget; steps rebuild themselves.
    final onIntro = useListenableSelector(
      draft.step,
      () => draft.step.value == HostStep.intro,
    );

    void exit() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('${AppRoutes.home}?tab=me');
      }
    }

    Future<bool> runSubmit() async {
      final user = session.userDocumentId;
      if (user == null) return false;
      try {
        final form = await ensureInterestForm();
        final input = HostSubmitPlan.build(
          draft,
          userDocumentId: user,
          form: form,
          me: me ?? UserWithExpert(user: session.user ?? const {}),
          onExpertId: (id) {
            draft.expertId = id;
            draft.flush();
          },
        );
        await submit.mutateAsync(input);
        await draft.clear();
        return true;
      } on ApiException catch (e) {
        await CAlert.error(e);
        return false;
      }
    }

    final p = HostPalette.of(context);
    return ThemedStatusBar(
      darkBackground: onIntro ? true : null,
      child: Scaffold(
        backgroundColor: onIntro ? IntroStep.deep : p.bg,
        resizeToAvoidBottomInset: false,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: onIntro
              ? IntroStep(
                  key: const ValueKey('intro'),
                  resuming: draft.started,
                  onStart: () {
                    draft.started = true;
                    draft.step.value = HostStep.basic;
                  },
                )
              : _Flow(
                  key: const ValueKey('flow'),
                  draft: draft,
                  submit: runSubmit,
                  exit: exit,
                  explore: () => context.go('${AppRoutes.home}?tab=discover'),
                  rateFloors: () =>
                      (pricing.minimumVoiceRate, pricing.minimumVideoRate),
                ),
        ),
      ),
    );
  }
}

/// Prefill from Personal Info (and, for a host resubmitting, the saved host
/// profile and topics) once the reads are in. Returns "my profile".
UserWithExpert? _usePrefill(
  BuildContext context,
  HostDraftController draft,
  SessionState session,
) {
  final me = useMyProfile(context);
  final isHost = session.isExpert;
  final host = useHostProfile(context, enabled: isHost);
  final expertise = useMyExpertise(context, enabled: isHost);
  final form = useInterestForm(context, enabled: isHost);
  final answers = useMyInterests(context, enabled: !isHost);

  final hostReady = !isHost || host.data != null || host.isError;
  final meReady = me.data != null || me.isError;
  useEffect(() {
    if (!meReady || !hostReady || draft.seeded) return null;
    HostPrefill.apply(
      draft,
      me.data ??
          UserWithExpert(
            user: session.user ?? const {},
            expert: session.expert,
          ),
      host: host.data,
      answers: answers.data?.selections ?? const {},
    );
    return null;
  }, [meReady, hostReady]);

  // The client's "How do you identify?" answer, if it arrives later.
  useEffect(() {
    final sel = answers.data?.selections;
    if (sel != null && draft.gender.value == null) {
      draft.gender.value = HostPrefill.genderFromAnswers(sel);
    }
    return null;
  }, [answers.data]);

  useEffect(() {
    final saved = expertise.data?.selections;
    if (saved == null || form.data == null || draft.topicsSeeded) return null;
    if (draft.topics.value.isEmpty) {
      draft.topics.value = HostTopicCatalog.selected(
        HostTopicCatalog.question(form.data),
        saved,
      );
    }
    draft.topicsSeeded = true;
    draft.flush();
    return null;
  }, [expertise.data, form.data]);
  return me.data;
}

class _Flow extends HookWidget {
  const _Flow({
    super.key,
    required this.draft,
    required this.submit,
    required this.exit,
    required this.explore,
    required this.rateFloors,
  });

  final HostDraftController draft;
  final Future<bool> Function() submit;
  final VoidCallback exit;
  final VoidCallback explore;
  final (double, double) Function() rateFloors;

  @override
  Widget build(BuildContext context) {
    final pages = usePageController(
      initialPage: draft.step.value.page.clamp(0, HostStep.pages.length - 1),
    );
    final flow = useMemoized(
      () => HostFlowController(
        draft: draft,
        pages: pages,
        submit: submit,
        exit: exit,
        explore: explore,
        rateFloors: rateFloors,
      ),
      [pages],
    );
    useEffect(() => flow.dispose, [flow]);

    final steps = <Widget>[
      for (final s in HostStep.pages)
        KeyedSubtree(key: ValueKey(s), child: _page(s, flow)),
    ];
    // Back gesture / Android back = the chevron (one step back).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) flow.back();
      },
      child: KeyboardInset(
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: HostProgressHeader(step: draft.step, onBack: flow.back),
            ),
            Expanded(
              child: PageView(
                controller: pages,
                physics: const NeverScrollableScrollPhysics(),
                children: steps,
              ),
            ),
            HostContinueBar(
              step: draft.step,
              busy: flow.busy,
              notice: draft.notice,
              agreed: draft.agreed,
              onPressed: flow.next,
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(HostStep s, HostFlowController flow) => switch (s) {
    HostStep.basic => BasicProfileStep(draft: draft),
    HostStep.interests => InterestsStep(draft: draft),
    HostStep.photos => PhotosStep(draft: draft),
    HostStep.tagline => TaglineStep(draft: draft),
    HostStep.bio => BioStep(draft: draft),
    HostStep.rates => RatesStep(draft: draft),
    HostStep.availability => AvailabilityStep(draft: draft),
    HostStep.preview => PreviewStep(draft: draft, onEdit: flow.editFrom),
    HostStep.guidelines => GuidelinesStep(draft: draft),
    _ => const SubmittedStep(),
  };
}
