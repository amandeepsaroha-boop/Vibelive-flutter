import 'package:image_picker/image_picker.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/component/upload_api.dart';

/// The device side of the profile photo, behind a seam so tests fake it:
/// pick from the library (image_picker) and upload (Strapi media).
abstract class PersonalInfoPhotoSource {
  const PersonalInfoPhotoSource();

  /// Swap in tests: `PersonalInfoPhotoSource.instance = _FakeSource();`.
  static PersonalInfoPhotoSource instance = const _DevicePhotoSource();

  /// Local path of the picked picture; null when the user cancelled.
  Future<String?> pick();

  /// Uploads [path]; returns the Strapi media node (`id`, `url`, …).
  Future<JsonMap> upload(String path) => UploadApi.uploadFile(path);
}

class _DevicePhotoSource extends PersonalInfoPhotoSource {
  const _DevicePhotoSource();

  @override
  Future<String?> pick() async {
    // RN: library only, quality 0.8. Capped size keeps uploads fast.
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 80,
    );
    return file?.path;
  }
}
