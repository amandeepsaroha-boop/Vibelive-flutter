import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/analytics/events/me_events.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/query/query_client.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/client/client_queries.dart';
import '../../../component/c_alert.dart';
import 'personal_info_controller.dart';
import 'photo_source.dart';

const _tag = 'PersonalInfo';
const _title = 'client:personal_info.title';

/// Save, photo and back flows of the screen (RN `handleSave`,
/// `handleImagePick` / `handleImageUpload`, `router.back`).
@immutable
class PersonalInfoActions {
  const PersonalInfoActions({
    required this.save,
    required this.changePhoto,
    required this.leave,
  });

  final Future<void> Function() save;
  final Future<void> Function() changePhoto;

  /// Back to whoever opened the screen (ME tab, a call gate, "Become a
  /// Host"); the ME tab when nothing is below (push / deep link).
  final VoidCallback leave;
}

PersonalInfoActions usePersonalInfoActions(
  BuildContext context,
  PersonalInfoController form,
) {
  final update = useUpdatePersonalInfo();

  final photo = useUpdateProfilePhoto(
    upload: (path) => PersonalInfoPhotoSource.instance.upload(path),
  );

  String? userId() =>
      form.profile?.documentId ?? SessionStore.instance.value.userDocumentId;

  /// RN re-read the user and pushed it into the auth store; this also
  /// mirrors it into [SessionStore] (ME tab, warn bar, call gates). The
  /// write already succeeded, so a failed re-read is only logged. [force]
  /// reloads the fields too (after a save; a photo keeps unsaved edits).
  Future<void> refresh(String id, {bool force = false}) async {
    try {
      final fresh = await ensureMyProfile(id, staleDuration: StaleTime.none);
      // The user may have left meanwhile (the form is then disposed).
      if (context.mounted) form.seed(fresh, force: force);
    } on ApiException catch (e) {
      Log.w(_tag, 'profile re-read failed: $e');
    }
  }

  void leave() {
    if (!context.mounted) return;
    PersonalInfoEvents.left(dirty: form.isDirty || form.genderChanged);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('${AppRoutes.home}?tab=me');
    }
  }

  Future<void> save() async {
    if (form.saving.value) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final changed = form.changedFields();
    final fields = changed.join(',');
    PersonalInfoEvents.saveTapped(fields: fields, count: changed.length);
    final issue = form.validate();
    if (issue != null) {
      PersonalInfoEvents.invalid(issue.name);
      await CAlert.show(
        title: _title,
        message: issue.messageKey,
        variant: CAlertVariant.warning,
      );
      return;
    }
    final id = userId();
    if (id == null || form.profile == null) {
      await CAlert.show(
        title: _title,
        message: 'client:personal_info.errors.missing_user',
        variant: CAlertVariant.error,
      );
      return;
    }

    // RN `wasProfileIncomplete`: this save finishes registration.
    final wasIncomplete = !form.profile!.isPersonalInfoComplete;
    form.saving.value = true;
    try {
      // Gender goes in the same public-user update (`gender`).
      await update.mutateAsync(form.input());
      form.markGenderSaved();
      PersonalInfoEvents.saved(
        fields: fields,
        count: changed.length,
        firstCompletion: wasIncomplete,
      );
      if (wasIncomplete) PersonalInfoEvents.userSignup(id);
      await refresh(id, force: true);
    } on ApiException catch (e) {
      PersonalInfoEvents.saveFailed(e);
      if (!context.mounted) return;
      form.saving.value = false;
      await CAlert.error(e, title: _title);
      return;
    }
    if (!context.mounted) return;
    form.saving.value = false;
    // Continue or dismiss: both go back (RN `onRequestClose` = continue).
    await CAlert.show(
      title: 'client:personal_info.success.profile_title',
      message: 'client:personal_info.success.profile_message',
      variant: CAlertVariant.success,
      primaryLabel: 'actions.continue',
    );
    leave();
  }

  Future<void> changePhoto() async {
    if (form.uploading.value) return;
    PersonalInfoEvents.photoTapped();
    String? path;
    try {
      path = await PersonalInfoPhotoSource.instance.pick();
    } catch (e) {
      Log.w(_tag, 'picker failed: $e');
      PersonalInfoEvents.photoFailed(stage: 'pick', error: e);
      await CAlert.show(
        title: 'client:personal_info.upload_title',
        message: 'client:personal_info.errors.pick_failed',
        variant: CAlertVariant.error,
      );
      return;
    }
    final id = userId();
    if (path == null) PersonalInfoEvents.photoCancelled();
    if (path == null || id == null || !context.mounted) return;

    form.uploading.value = true;
    try {
      await photo.mutateAsync(path);
      PersonalInfoEvents.photoUpdated();
      await refresh(id);
    } on ApiException catch (e) {
      PersonalInfoEvents.photoFailed(stage: 'upload', error: e);
      if (!context.mounted) return;
      form.uploading.value = false;
      await CAlert.error(e, title: 'client:personal_info.upload_error_title');
      return;
    }
    if (!context.mounted) return;
    form.uploading.value = false;
    // Photo: the modal only closes, the user stays on the screen.
    await CAlert.show(
      title: 'client:personal_info.success.photo_title',
      message: 'client:personal_info.success.photo_message',
      variant: CAlertVariant.success,
      primaryLabel: 'actions.continue',
    );
  }

  return PersonalInfoActions(
    save: save,
    changePhoto: changePhoto,
    leave: leave,
  );
}
