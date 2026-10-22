import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import '../../../core/utils/log.dart';
import 'profile_models.dart';
import 'strapi_lookup.dart';

/// The host's own `/expert-profiles` record. Raw calls only: use the hooks
/// in `hosthub_queries.dart`.
abstract final class HostProfileApi {
  /// Relations every host screen reads.
  static const populate = <String, dynamic>{
    'populate[audio_intro]': 'true',
    'populate[language]': 'true',
    'populate[rates]': 'true',
    'populate[durations]': 'true',
    'populate[schedule][populate][0]': 'timeSlots',
    'populate[expert_profile_approvals]': 'true',
    'populate[expert_verifications]': 'true',
    'populate[service_area_selections]': 'true',
    'populate[host_profile_images][populate][image]': 'true',
  };

  /// Null when the record cannot be found even through the fallbacks.
  /// [ownerUserDocumentId] (the signed-in user) enables the last fallback.
  static Future<HostProfile?> fetchById(
    String expertId, {
    String? ownerUserDocumentId,
  }) async {
    try {
      final body = await ApiClient.get(
        '/expert-profiles/${Uri.encodeComponent(expertId)}',
        query: populate,
      );
      return HostProfile.fromResponse(body);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      return _recover(expertId, ownerUserDocumentId);
    }
  }

  /// The host profile owned by a user (null for a non-host).
  static Future<HostProfile?> fetchByUser(String userDocumentId) async {
    final row = await StrapiLookup.fetchLatest(
      '/expert-profiles',
      StrapiLookup.relationFilters('user', userDocumentId),
      query: populate,
    );
    return HostProfile.from(row);
  }

  /// The created record; throws when the response carries none.
  static Future<HostProfile> create(JsonMap data) async {
    final created = HostProfile.fromResponse(
      await ApiClient.post('/expert-profiles', data: {'data': data}),
    );
    if (created == null) {
      throw const ApiException(
        ApiErrorType.parse,
        messageKey: 'hosthub:errors.create_profile_failed',
      );
    }
    return created;
  }

  /// The PUT response (relations not populated).
  static Future<HostProfile?> update(String expertId, JsonMap data) async {
    try {
      return HostProfile.fromResponse(
        await ApiClient.put(
          '/expert-profiles/${Uri.encodeComponent(expertId)}',
          data: {'data': data},
        ),
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404 || StrapiLookup.isNumericId(expertId)) rethrow;
      // Some backend routes accept the numeric id only: resolve it from the
      // documentId and retry once.
      final rows = StrapiLookup.rowsOf(
        await ApiClient.get(
          '/expert-profiles',
          query: {
            'filters[documentId][\$eq]': expertId,
            'pagination[page]': 1,
            'pagination[pageSize]': 1,
          },
        ),
      );
      final numericId = rows.isEmpty ? null : J.str(rows.first['id']);
      if (numericId == null) rethrow;
      return HostProfile.fromResponse(
        await ApiClient.put(
          '/expert-profiles/$numericId',
          data: {'data': data},
        ),
      );
    }
  }

  /// GET /expert-profiles/:id is scoped on this backend: a freshly created
  /// host profile answers 404 although it exists, which made the first save
  /// of every new host look failed. Try the list endpoint, then the owner's
  /// own profile, accepted only when it is the record asked for (this path
  /// is also reached for other hosts). Both are best effort, as in RN.
  static Future<HostProfile?> _recover(String expertId, String? owner) async {
    try {
      final row = await StrapiLookup.fetchLatest(
        '/expert-profiles',
        StrapiLookup.ownIdFilters(expertId),
        query: populate,
      );
      if (row != null) return HostProfile.from(row);
    } on ApiException catch (e) {
      Log.w('HostProfileApi', 'list fallback failed: $e');
    }
    if (owner == null || owner.isEmpty) return null;
    try {
      final mine = await fetchByUser(owner);
      return mine != null && mine.isSameRecord(expertId) ? mine : null;
    } on ApiException catch (e) {
      Log.w('HostProfileApi', 'owner fallback failed: $e');
      return null;
    }
  }
}
