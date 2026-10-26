import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../component/upload_api.dart';
import 'client_models.dart';
import 'geo_api.dart';

/// `/public-users`: the signed-in user's profile (read, personal info, photo)
/// and the user + expert read other features reuse.
abstract final class ProfileApi {
  static const _withExpertPopulate = <String, dynamic>{
    'populate[profilePic]': true,
    'populate[platform]': true,
    'populate[state]': true,
    'populate[district]': true,
    'populate[city]': true,
    'populate[country]': true,
    'populate[expert][populate][language]': true,
    'populate[expert][populate][rates]': true,
    'populate[expert][populate][durations]': true,
    'populate[expert][populate][schedule][populate][0]': 'timeSlots',
    'populate[expert][populate][expert_profile_approvals]': true,
    'populate[expert][populate][expert_verifications]': true,
    // Host photos: the host editor reloads through this call and decides
    // update-vs-create from these rows (missing ⇒ duplicate rows on save).
    'populate[expert][populate][host_profile_images][populate][image]': true,
  };

  static const _menuRelationsPopulate = <String, dynamic>{
    'populate[profilePic]': true,
    'populate[user_referral]': true,
    'populate[gst_detail][populate][GST][populate][0]': 'state',
    'populate[gst_detail][populate][GST][populate][1]': 'district',
    'populate[gst_detail][populate][GST][populate][2]': 'city',
    'populate[gst_detail][populate][GST][populate][3]': 'GST_File',
    'populate[gst_detail][populate][GST][populate][4]': 'Logo',
    'populate[gst_detail][populate][gst_device_info]': true,
  };

  /// A user with their expert profile (RN `fetchUserWithExpert`).
  static Future<UserWithExpert> fetchUserWithExpert(
    String userDocumentId,
  ) async {
    JsonMap? user;
    try {
      user = Strapi.map(
        Strapi.body(
          await ApiClient.get(
            '/public-users/${Uri.encodeComponent(userDocumentId)}',
            query: _withExpertPopulate,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (e.type != ApiErrorType.notFound) rethrow;
      // Some deployments resolve a documentId only through list + filters.
      final rows = Strapi.list(
        await ApiClient.get(
          '/public-users',
          query: {
            r'filters[documentId][$eq]': userDocumentId,
            'pagination[page]': 1,
            'pagination[pageSize]': 1,
            ..._withExpertPopulate,
          },
        ),
      );
      user = rows.isEmpty ? null : rows.first;
    }
    if (user == null || user.isEmpty) {
      throw const ApiException(
        ApiErrorType.notFound,
        messageKey: 'client:errors.profile_not_found',
      );
    }
    return UserWithExpert.fromUser(user);
  }

  /// The user with referral and GST relations (Referral, GST screens).
  static Future<JsonMap?> fetchUserWithMenuRelations(
    String userDocumentId,
  ) async => Strapi.map(
    Strapi.body(
      await ApiClient.get(
        '/public-users/${Uri.encodeComponent(userDocumentId)}',
        query: _menuRelationsPopulate,
      ),
    ),
  );

  /// `PUT /public-users/:id` with `{data: data}`.
  static Future<void> updatePublicUser(
    String userDocumentId,
    JsonMap data,
  ) async {
    await ApiClient.put(
      '/public-users/${Uri.encodeComponent(userDocumentId)}',
      data: {'data': data},
    );
  }

  /// Personal Info save. Unique-constraint failures on email / mobile come
  /// back with `client:errors.email_taken` / `mobile_taken`.
  static Future<void> updatePersonalInfo(
    String userDocumentId,
    PersonalInfoInput input, {
    GeoOption? country,
  }) async {
    try {
      await updatePublicUser(userDocumentId, input.toData(country: country));
    } on ApiException catch (e) {
      throw mapSaveError(e);
    }
  }

  /// Uploads [filePath] and sets it as the profile photo. Returns the media.
  static Future<JsonMap> updateProfilePhoto(
    String userDocumentId,
    String filePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = await UploadApi.uploadFile(filePath, onProgress: onProgress);
    await setProfilePhoto(userDocumentId, file['id']);
    return file;
  }

  /// Makes an already uploaded media ([mediaId]) the profile photo.
  static Future<void> setProfilePhoto(String userDocumentId, Object? mediaId) {
    if (mediaId == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: 'errors.upload_failed',
      );
    }
    return updatePublicUser(userDocumentId, {'profilePic': mediaId});
  }

  /// Strapi reports a duplicate email / mobile as a generic validation error;
  /// name the field instead (RN `getPersonalInfoSaveErrorMessage`).
  static ApiException mapSaveError(ApiException e) {
    final body = e.data is Map ? e.data! as Map : const {};
    final root = body['error'] is Map ? body['error'] as Map : const {};
    final details = root['details'] ?? body['details'] ?? const {};
    final errors = details is Map && details['errors'] is List
        ? details['errors'] as List
        : const [];
    final joined = _jsonText(details).toLowerCase();
    final message = '${root['message'] ?? body['message'] ?? ''}'.toLowerCase();

    final isUnique =
        message.contains('unique') ||
        joined.contains('must be unique') ||
        joined.contains('already taken');
    if (!isUnique) return e;

    bool mentions(String field) =>
        errors.any(
          (x) =>
              x is Map &&
              '${x['path'] ?? x['message'] ?? ''}'.toLowerCase().contains(
                field,
              ),
        ) ||
        joined.contains(field);

    final key = mentions('email')
        ? 'client:errors.email_taken'
        : mentions('mobile')
        ? 'client:errors.mobile_taken'
        : null;
    if (key == null) return e;
    // No serverMessage: it would win over our key in `localizedMessage`.
    return ApiException(
      e.type,
      statusCode: e.statusCode,
      messageKey: key,
      data: e.data,
      cause: e.cause,
      stackTrace: e.stackTrace,
    );
  }

  static String _jsonText(Object? v) {
    try {
      return jsonEncode(v);
    } catch (_) {
      return '$v';
    }
  }
}

/// Public-user `gender` enum: `male` / `female` / `prefer_not_to_say`
/// (the app's chips are Male / Female / Others).
String? userGenderValue(String? gender) => switch (gender) {
  'Male' => 'male',
  'Female' => 'female',
  'Others' => 'prefer_not_to_say',
  _ => null,
};

/// The public-user `gender` enum value as the app's chip value.
String? userGenderLabel(Object? value) =>
    switch ('${value ?? ''}'.trim().toLowerCase()) {
      'male' => 'Male',
      'female' => 'Female',
      'prefer_not_to_say' || 'other' || 'others' => 'Others',
      _ => null,
    };

/// Personal Info form values plus the profile they edit ([current]): email
/// and mobile are only sent when they changed (both are unique server-side).
class PersonalInfoInput {
  const PersonalInfoInput({
    required this.current,
    required this.name,
    required this.email,
    required this.mobile,
    required this.state,
    this.district,
    this.gender,
  });

  final UserWithExpert current;

  /// `Female` / `Male` / `Others` (public-user `gender`); null = unchanged.
  final String? gender;
  final String name;
  final String email;
  final String mobile;
  final GeoOption state;
  final GeoOption? district;

  JsonMap toData({GeoOption? country}) {
    final existingEmail = (current.email ?? '').toLowerCase();
    final existingMobile = _digits(current.mobile ?? '');
    final nextEmail = email.trim().toLowerCase();
    final nextMobile = _digits(mobile);
    return {
      'name': name.trim(),
      'gender': ?userGenderValue(gender),
      'state': ?state.connect,
      'district': ?district?.connect,
      'city': null,
      'address_JSON': {
        ...current.addressJson,
        'city': '',
        'state': state.name,
        'district': district?.name ?? '',
        'country': GeoApi.defaultCountry,
      },
      'country': ?country?.connect,
      'profilePic': ?current.profilePicId,
      if (nextEmail.isNotEmpty && nextEmail != existingEmail)
        'email': nextEmail,
      if (nextMobile.isNotEmpty && nextMobile != existingMobile)
        'mobile': nextMobile,
    };
  }

  /// Digits only, at most 10 (Indian mobile).
  static String _digits(String s) {
    final d = s.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(0, 10) : d;
  }
}
