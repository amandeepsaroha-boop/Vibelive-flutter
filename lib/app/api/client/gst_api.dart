import '../../../core/network/api_client.dart';
import '../../../core/network/strapi.dart';
import '../component/upload_api.dart';
import 'client_models.dart';
import 'profile_api.dart';

/// `/gst-details`: read through the user record, create or update.
abstract final class GstApi {
  static Future<GstDetails> fetchGstDetails(String userDocumentId) async =>
      GstDetails.fromUser(
        await ProfileApi.fetchUserWithMenuRelations(userDocumentId),
      );


  /// Uploads the picked files, then creates the record — or updates it when
  /// [GstDetailsInput.gstDetailId] is set (a second POST is a 400 duplicate).
  /// Returns the saved row (its documentId links it to a verification).
  static Future<JsonMap?> saveGstDetails(
    String userDocumentId,
    GstDetailsInput input,
  ) async {
    Object? gstFileId = input.gstFileId;
    Object? logoId = input.logoId;
    // Files are only attached to a GST registration.
    if (input.hasGstRegistration) {
      final gstFilePath = input.gstFilePath;
      final logoPath = input.logoPath;
      if (gstFilePath != null) {
        gstFileId = (await UploadApi.uploadFile(gstFilePath))['id'];
      }
      if (logoPath != null) {
        logoId = (await UploadApi.uploadFile(logoPath))['id'];
      }
    }
    return createOrUpdate(
      input.toData(userDocumentId, gstFileId: gstFileId, logoId: logoId),
      gstDetailId: input.gstDetailId,
    );
  }

  /// Raw write for callers that already built the Strapi `data` (RN
  /// `createOrUpdateGstDetail`): PUT when [gstDetailId] is set, else POST.
  static Future<JsonMap?> createOrUpdate(
    JsonMap data, {
    String? gstDetailId,
  }) async {
    final body = (gstDetailId != null && gstDetailId.isNotEmpty)
        ? await ApiClient.put(
            '/gst-details/${Uri.encodeComponent(gstDetailId)}',
            data: {'data': data},
          )
        : await ApiClient.post('/gst-details', data: {'data': data});
    return Strapi.map(Strapi.body(body));
  }
}

/// GST form values. Not registered ⇒ only the declaration is saved.
class GstDetailsInput {
  const GstDetailsInput({
    this.gstDetailId,
    this.hasGstRegistration = true,
    this.declarationStatement,
    this.gstNumber = '',
    this.businessName = '',
    this.address = '',
    this.zipcode = '',
    this.state,
    this.district,
    this.city,
    this.gstFilePath,
    this.logoPath,
    this.gstFileId,
    this.logoId,
  });

  /// [GstDetails.documentId] of the existing record, if any.
  final String? gstDetailId;
  final bool hasGstRegistration;

  /// Required text when not registered.
  final String? declarationStatement;
  final String gstNumber;
  final String businessName;
  final String address;
  final String zipcode;
  final GeoOption? state;
  final GeoOption? district;
  final GeoOption? city;

  /// Local files to upload first.
  final String? gstFilePath;
  final String? logoPath;

  /// Media ids already uploaded (used when no path is given).
  final Object? gstFileId;
  final Object? logoId;

  JsonMap toData(
    String userDocumentId, {
    Object? gstFileId,
    Object? logoId,
    DateTime? now,
  }) {
    final at = (now ?? DateTime.now()).toUtc();
    final declaration = declarationStatement?.trim() ?? '';
    final address = this.address.trim();
    return {
      'user': userDocumentId,
      'gst_device_info': {
        'ip_address': null,
        'device_id': null,
        'is_gst_registered': hasGstRegistration,
        // JS `toISOString()` precision (milliseconds).
        'declaration_date': DateTime.fromMillisecondsSinceEpoch(
          at.millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String(),
        'declaration_statement': (hasGstRegistration || declaration.isEmpty)
            ? null
            : declaration,
      },
      if (hasGstRegistration)
        'GST': {
          'GST_Number': gstNumber.trim().toUpperCase(),
          'Business_Name': businessName.trim(),
          'Address': address,
          'addressLine': address,
          'zipcode': zipcode.trim(),
          'state': ?state?.relationId,
          'district': ?district?.relationId,
          'city': ?city?.relationId,
          'GST_File': ?_present(gstFileId ?? this.gstFileId),
          'Logo': ?_present(logoId ?? this.logoId),
        },
    };
  }

  static Object? _present(Object? v) => (v == null || v == '') ? null : v;
}
