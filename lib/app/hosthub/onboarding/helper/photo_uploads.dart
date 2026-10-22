import '../../../../core/network/api_exception.dart';
import '../../../../core/network/strapi.dart';
import '../../../component/c_toast.dart';
import 'draft_controller.dart';
import 'draft_models.dart';
import 'photo_picker.dart';
import 'validation.dart';

/// Photos step actions. A picked photo uploads right away (media only; it is
/// attached to the host profile at submit), so the draft keeps media ids
/// rather than temp files that may vanish before the next launch.
class HostPhotoUploads {
  HostPhotoUploads(this.draft);
  final HostDraftController draft;
  int _seq = 0;

  bool get canAdd => draft.photos.value.length < HostValidation.maxPhotos;

  Future<void> add(HostPhotoOrigin origin) async {
    if (!canAdd) return;
    final String? path;
    try {
      path = await HostPhotoPicker.instance.pick(origin);
    } catch (e) {
      // Permission denied or no camera: say so, keep the step usable.
      draft.notice.value = (
        key: 'hostflow:photos.pick_failed',
        variables: null,
      );
      return;
    }
    if (path == null || draft.isDisposed || !canAdd) return;
    final photo = HostDraftPhoto(
      key: 'l${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
      localPath: path,
    );
    draft.photos.value = [...draft.photos.value, photo];
    await _upload(photo);
  }

  Future<void> retry(HostDraftPhoto photo) async {
    draft.updatePhoto(photo.key, (p) => p.copyWith(failed: false));
    await _upload(photo);
  }

  void remove(HostDraftPhoto photo) => draft.photos.value = [
    for (final p in draft.photos.value)
      if (p.key != photo.key) p,
  ];

  /// Moves [photo] to slot 1 (the primary photo).
  void makePrimary(HostDraftPhoto photo) => draft.photos.value = [
    photo,
    for (final p in draft.photos.value)
      if (p.key != photo.key) p,
  ];

  Future<void> _upload(HostDraftPhoto photo) async {
    final path = photo.localPath;
    if (path == null) return;
    try {
      final media = await HostPhotoPicker.instance.upload(path);
      if (draft.isDisposed) return;
      final id = media['id'] ?? media['documentId'];
      if (id == null) {
        throw const ApiException(
          ApiErrorType.parse,
          messageKey: 'errors.upload_failed',
        );
      }
      draft.updatePhoto(
        photo.key,
        (p) => p.copyWith(mediaId: id, url: Strapi.mediaFromAsset(media)),
      );
    } catch (e) {
      if (draft.isDisposed) return;
      draft.updatePhoto(photo.key, (p) => p.copyWith(failed: true));
      CToast.error(e);
    }
  }
}
