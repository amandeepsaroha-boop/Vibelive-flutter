import '../../../../core/analytics/analytics.dart';
import '../../../../core/analytics/events/host_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
import '../../../api/hosthub/profile_models.dart';
import 'draft_controller.dart';
import 'host_steps.dart';

/// The "Become a Host" funnel for analytics, one per open of the flow:
/// a view per step change (`draft.step` is the single source), the
/// completions [HostFlowController] reports, and the exit. Each step is
/// also the page's analytics sub-screen (`host_onboarding_<step>`).
class HostFunnel {
  HostFunnel({
    required this.draft,
    required this.mode,
    required this.source,
    required this.routePath,
  });

  final HostDraftController draft;

  /// `new` | `resume` | `edit` | `existing_host`.
  final String mode;

  /// Where the flow was opened from (`become_host`, `host_hub`, `deeplink`…).
  final String source;

  /// The route this screen is on (its sub-screens are keyed by it).
  final String routePath;

  late HostStep _last;
  bool _started = false;
  bool _finished = false;

  /// The flow went in (submitted, or an existing host's save).
  bool get finished => _finished;

  void start() {
    if (_started) return;
    _started = true;
    _last = draft.step.value;
    HostEvents.onboardingStarted(
      mode: mode,
      startStep: _last.name,
      stepNumber: _last.number,
      source: source,
    );
    _viewed(_last);
    draft.step.addListener(_onStep);
  }

  void _onStep() {
    final s = draft.step.value;
    if (s == _last) return;
    _last = s;
    _viewed(s);
  }

  void _viewed(HostStep s) {
    HostEvents.stepViewed(
      s.name,
      stepNumber: s.number,
      mode: mode,
      source: source,
    );
    ScreenTracker.setSubScreen(routePath, 'host_onboarding_${s.name}', {
      'step_number': s.number,
      'mode': mode,
    });
  }

  /// Continue on [step] passed its checks.
  void completed(HostStep step) {
    HostEvents.stepCompleted(
      step.name,
      stepNumber: step.number,
      mode: mode,
      source: source,
    );
    if (step == HostStep.interests && (mode == 'new' || mode == 'resume')) {
      final topics = draft.topics.value;
      HostEvents.specializationSelected(
        expertId: draft.expertId,
        categoryIds: [for (final t in topics) t.value],
        categoryNames: [for (final t in topics) t.label],
        source: 'onboarding',
      );
    }
  }

  void back(HostStep from) =>
      HostEvents.stepBack(from.name, stepNumber: from.number, mode: mode);

  void invalid(HostStep step, String issue) =>
      HostEvents.validationFailed(step.name, issue: issue, mode: mode);

  void handleTaken() => HostEvents.handleTaken(mode: mode);

  void previewEdit(HostStep section) =>
      HostEvents.previewEditTapped(section.name);

  /// The application went in ([userKey]: for RN's once-per-user
  /// `expert_signup`).
  void submitted(String? userKey) {
    _finished = true;
    final topics = draft.topics.value;
    HostEvents.onboardingSubmitted(
      userKey: userKey,
      category: topics.isEmpty ? null : topics.first.label,
      topicsCount: topics.length,
      photosCount: draft.photos.value.length,
      hasVoiceIntro: draft.voiceIntro.value != null,
      audioRate: draft.audioOn.value ? draft.audioRate.value : null,
      videoRate: draft.videoOn.value ? draft.videoRate.value : null,
      source: source,
    );
  }

  void submitFailed(Object error, HostStep? failedStep) =>
      HostEvents.submitFailed(
        error: Analytics.errorCode(error),
        failedStep: failedStep?.name,
      );

  /// An existing host saved (one section, or `all` on the last step).
  void saved(String step) {
    _finished = true;
    HostEvents.sectionSaved(step, mode: mode);
  }

  void dispose() {
    if (!_started) return;
    draft.step.removeListener(_onStep);
    HostEvents.onboardingExited(
      lastStep: _last.name,
      stepNumber: _last.number,
      completed: _finished || _last == HostStep.submitted,
      mode: mode,
      source: source,
    );
    ScreenTracker.clearSubScreen(routePath);
  }
}

/// A host's availability as analytics names it: `online` (call any time),
/// `offline` (vacation) or `scheduled` (working hours).
String hostStatusName(HostAvailability mode) => switch (mode) {
  HostAvailability.available => 'online',
  HostAvailability.vacation => 'offline',
  HostAvailability.custom => 'scheduled',
};
