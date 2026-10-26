import 'package:flutter/widgets.dart';

import '../../../api/hosthub/hosthub_queries.dart';
import '../../../component/c_toast.dart';
import 'draft_controller.dart';
import 'host_steps.dart';
import 'validation.dart';

/// Back / Continue for the form steps: validates the current step, waits
/// on the handle check, runs the submit, and moves the page view.
class HostFlowController {
  HostFlowController({
    required this.draft,
    required this.pages,
    required this.submit,
    required this.exit,
    required this.explore,
    required this.rateFloors,
    this.editing = false,
    this.saveAll,
    this.existingHost,
  });

  final HostDraftController draft;
  final PageController pages;

  /// The whole submit: null when the profile went in, else the step to send
  /// the user back to (the one owning the field the server rejected).
  final Future<HostStep?> Function() submit;

  /// Leave the flow (back on the intro / success screen).
  final VoidCallback exit;

  /// "Explore VibeLive" on the success screen.
  final VoidCallback explore;

  /// Pricing floors for the rates check: `(voice, video)`.
  final (double, double) Function() rateFloors;

  /// A host editing from the Host Hub: Back before the first form step
  /// leaves instead of showing the intro.
  final bool editing;

  /// An existing host (approved, live or pending review): the last step
  /// saves every section with [saveAll] (null when saved, else the step to
  /// go back to) and returns to the Host Hub instead of submitting.
  final Future<HostStep?> Function()? saveAll;
  final bool Function()? existingHost;

  bool get savesInstead => saveAll != null && (existingHost?.call() ?? false);

  /// Continue shows a spinner and ignores taps while true.
  final busy = ValueNotifier(false);

  static const _duration = Duration(milliseconds: 300);

  /// Set by a preview "Edit" link: Continue / Back on the edited step go
  /// straight back to the preview.
  HostStep? returnTo;

  Future<void> goTo(HostStep step) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final from = draft.step.value;
    draft.step.value = step;
    draft.flush();
    if (step == HostStep.intro || !pages.hasClients) return;
    if ((step.index - from.index).abs() > 1) {
      // Jumps (preview edits) skip the steps in between.
      pages.jumpToPage(step.page);
      return;
    }
    await pages.animateToPage(
      step.page,
      duration: _duration,
      curve: Curves.easeOutCubic,
    );
  }

  /// Preview "Edit": open [step], come back to the preview after it.
  Future<void> editFrom(HostStep step) {
    returnTo = draft.step.value;
    return goTo(step);
  }

  /// Where Continue / Back lead after an edit, consuming it.
  HostStep? _takeReturn() {
    final r = returnTo;
    returnTo = null;
    return r;
  }

  void back() {
    if (busy.value) return;
    final step = draft.step.value;
    if (step == HostStep.intro ||
        step == HostStep.submitted ||
        (editing && step == HostStep.basic && returnTo == null)) {
      exit();
      return;
    }
    goTo(_takeReturn() ?? step.previous!);
  }

  Future<void> next() async {
    if (busy.value) return;
    final step = draft.step.value;
    if (step == HostStep.submitted) {
      explore();
      return;
    }
    final (voice, video) = rateFloors();
    final issue = HostValidation.check(
      step,
      draft,
      minVoiceRate: voice,
      minVideoRate: video,
    );
    if (issue != null) {
      draft.notice.value = issue;
      return;
    }
    if (step == HostStep.basic && !await _handleIsFree()) return;
    if (step == HostStep.guidelines) {
      final saving = savesInstead;
      busy.value = true;
      final failedAt = await (saving ? saveAll!() : submit()).whenComplete(
        () => busy.value = false,
      );
      if (failedAt != null) {
        if (failedAt != step) await goTo(failedAt);
        return;
      }
      if (saving) {
        // Saved: no approval request, no "Submitted" step.
        await draft.clear();
        exit();
        return;
      }
    }
    await goTo(_takeReturn() ?? step.next!);
  }

  Future<bool> _handleIsFree() async {
    busy.value = true;
    try {
      final free = await ensureHostHandleCheck(
        draft.handle.text,
        ownExpertId: draft.expertId,
      );
      if (!free) {
        draft.notice.value = (
          key: 'hostflow:errors.handle_taken',
          variables: null,
        );
      }
      return free;
    } catch (e) {
      CToast.error(e);
      return false;
    } finally {
      busy.value = false;
    }
  }

  void dispose() => busy.dispose();
}
