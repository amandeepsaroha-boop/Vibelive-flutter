import 'package:image_picker/image_picker.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/component/upload_api.dart';

/// The photos a payout account is checked against: the passbook or a
/// cancelled cheque, and both sides of the PAN card.
enum BankDocKind {
  bankProof('Bank_Proof', 'bank_proof'),
  panFront('PAN_Front', 'pan_front'),
  panBack('PAN_Back', 'pan_back');

  const BankDocKind(this.field, this.key);

  /// The backend's attribute name.
  final String field;

  /// Snake-case name for i18n keys and analytics.
  final String key;

  String get labelKey => 'payment:bank.docs.$key';
  String get errorKey => 'payment:bank.errors.$key';
}

enum BankDocOrigin { gallery, camera }

/// One document photo as the form holds it: picked, uploading, uploaded or
/// failed (tap to retry).
class BankDoc {
  const BankDoc({this.mediaId, this.url, this.localPath, this.failed = false});

  final Object? mediaId;
  final String? url;
  final String? localPath;
  final bool failed;

  bool get uploaded => mediaId != null;
  bool get uploading => mediaId == null && !failed && localPath != null;
}

/// The device side of a document photo, behind a seam so tests fake it:
/// pick (image_picker) and upload (Strapi media).
abstract class BankDocSource {
  const BankDocSource();

  /// Swap in tests: `BankDocSource.instance = _FakeSource();`.
  static BankDocSource instance = const _DeviceDocSource();

  /// Local path of the picked picture; null when the user cancelled.
  Future<String?> pick(BankDocOrigin origin);

  /// Uploads [path]; returns the Strapi media node (`id`, `url`, …).
  Future<JsonMap> upload(String path) => UploadApi.uploadFile(path);
}

class _DeviceDocSource extends BankDocSource {
  const _DeviceDocSource();

  @override
  Future<String?> pick(BankDocOrigin origin) async {
    final file = await ImagePicker().pickImage(
      source: origin == BankDocOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      // Large enough for the team to read an account number or PAN, small
      // enough to upload on a slow connection.
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    return file?.path;
  }
}
