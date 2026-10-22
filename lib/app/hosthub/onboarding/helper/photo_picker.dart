import 'package:image_picker/image_picker.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/component/upload_api.dart';

enum HostPhotoOrigin { gallery, camera }

/// The device side of the Photos step, behind a seam so tests fake it:
/// pick a picture (image_picker) and upload it (Strapi media).
abstract class HostPhotoPicker {
  const HostPhotoPicker();

  /// Swap in tests: `HostPhotoPicker.instance = _FakePicker();`.
  static HostPhotoPicker instance = const _DevicePhotoPicker();

  /// Local path of the picked picture; null when the user cancelled.
  Future<String?> pick(HostPhotoOrigin origin);

  /// Uploads [path]; returns the Strapi media node (`id`, `url`, …).
  Future<JsonMap> upload(String path);
}

class _DevicePhotoPicker extends HostPhotoPicker {
  const _DevicePhotoPicker();

  @override
  Future<String?> pick(HostPhotoOrigin origin) async {
    final file = await ImagePicker().pickImage(
      source: origin == HostPhotoOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Profile photos never need more: keeps uploads small and fast.
      maxWidth: 1440,
      maxHeight: 1440,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    return file?.path;
  }

  @override
  Future<JsonMap> upload(String path) => UploadApi.uploadFile(path);
}
