import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import '../../../api/client/client_models.dart';
import '../../../api/client/gst_api.dart';

/// Picks a GST certificate / logo from the library; tests swap [instance].
abstract class GstImageSource {
  const GstImageSource();
  static GstImageSource instance = const _LibrarySource();

  /// Local path, or null when cancelled.
  Future<String?> pick();
}

class _LibrarySource extends GstImageSource {
  const _LibrarySource();

  @override
  Future<String?> pick() async => (await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 80,
  ))?.path;
}

/// GST Details form state (RN GstDetailsScreen `useState`s + `validate`).
class GstForm extends ChangeNotifier {
  GstForm() {
    for (final c in [number, business, address, zipcode]) {
      c.addListener(notifyListeners);
    }
  }

  static final gstPattern = RegExp(
    r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9]Z[A-Z0-9]$',
  );

  final number = TextEditingController();
  final business = TextEditingController();
  final address = TextEditingController();
  final zipcode = TextEditingController();

  bool seeded = false;
  bool submitted = false;
  bool editMode = true;
  bool hasRegistration = true;
  bool declarationConfirmed = false;
  GeoOption? state;
  GeoOption? district;
  String? gstDetailId;

  /// Picked on this device (uploaded on save).
  String? gstFilePath;
  String? logoPath;

  /// Already on the server.
  String? gstFileUrl;
  String? logoUrl;
  Object? gstFileId;
  Object? logoId;

  /// Field → i18n key of its error.
  final errors = <String, String>{};

  bool get editable => editMode || !submitted;

  /// First read only: later refetches never overwrite what is typed.
  void seed(GstDetails d) {
    if (seeded) return;
    seeded = true;
    submitted = d.isSubmitted;
    editMode = !submitted;
    gstDetailId = d.documentId;
    hasRegistration = d.isGstRegistered || !d.isSubmitted;
    declarationConfirmed =
        !hasRegistration && d.declarationStatement.isNotEmpty;
    number.text = d.gstNumber;
    business.text = d.businessName;
    address.text = d.address;
    zipcode.text = d.zipcode;
    state = d.state;
    district = state == null ? null : d.district;
    gstFileUrl = d.gstFileUrl;
    logoUrl = d.logoUrl;
    gstFileId = d.gstFile?['id'];
    logoId = d.logo?['id'];
    notifyListeners();
  }

  void toggleEdit() {
    editMode = !editMode;
    notifyListeners();
  }

  void setRegistration(bool value) {
    hasRegistration = value;
    if (value) declarationConfirmed = false;
    errors.remove('declaration');
    notifyListeners();
  }

  void toggleDeclaration() {
    declarationConfirmed = !declarationConfirmed;
    errors.remove('declaration');
    notifyListeners();
  }

  void clearError(String field) {
    if (errors.remove(field) != null) notifyListeners();
  }

  void setState(GeoOption? value) {
    state = value;
    district = null;
    notifyListeners();
  }

  void setDistrict(GeoOption? value) {
    district = value;
    notifyListeners();
  }

  void setGstFile(String path) {
    gstFilePath = path;
    notifyListeners();
  }

  void setLogo(String path) {
    logoPath = path;
    notifyListeners();
  }

  /// RN `validate`; fills [errors].
  bool validate() {
    errors.clear();
    if (hasRegistration) {
      final n = number.text.trim().toUpperCase();
      if (n.isEmpty) {
        errors['number'] = 'resources:gst.errors.number_required';
      } else if (!gstPattern.hasMatch(n)) {
        errors['number'] = 'resources:gst.errors.number_invalid';
      }
      if (business.text.trim().isEmpty) {
        errors['business'] = 'resources:gst.errors.business_required';
      }
      if (address.text.trim().isEmpty) {
        errors['address'] = 'resources:gst.errors.address_required';
      }
    } else if (!declarationConfirmed) {
      errors['declaration'] = 'resources:gst.errors.declaration_required';
    }
    notifyListeners();
    return errors.isEmpty;
  }

  /// What `useSaveGstDetails` sends. Updates the existing row (RN posted a
  /// new one every time, which the backend rejects as a duplicate).
  GstDetailsInput input(String declarationStatement) => GstDetailsInput(
    gstDetailId: gstDetailId,
    hasGstRegistration: hasRegistration,
    declarationStatement: declarationConfirmed ? declarationStatement : null,
    gstNumber: number.text.trim().toUpperCase(),
    businessName: business.text.trim(),
    address: address.text.trim(),
    zipcode: zipcode.text.trim(),
    state: state,
    district: district,
    gstFilePath: gstFilePath,
    logoPath: logoPath,
    gstFileId: gstFileId,
    logoId: logoId,
  );

  /// [savedId]: the row's documentId, so the next save updates it.
  void markSaved(String? savedId) {
    gstDetailId = savedId ?? gstDetailId;
    submitted = true;
    editMode = false;
    errors.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in [number, business, address, zipcode]) {
      c.dispose();
    }
    super.dispose();
  }
}
