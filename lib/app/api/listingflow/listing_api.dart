import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'listing_models.dart';

/// Reading other hosts' expert profiles. Single-host reads go through the
/// filtered LIST endpoint: `GET /expert-profiles/:documentId` can 404 on
/// this backend.
abstract final class ListingApi {
  /// Everything [HostCard] reads: the Discover feed, Popular, search and
  /// deep-link profiles all use it. `host_profile_images` feeds the gallery
  /// carousel; without it the card falls back to the single profile pic.
  static const hostCardPopulate = <String, dynamic>{
    'populate[user][populate][profilePic]': 'true',
    'populate[user][populate][district]': 'true',
    'populate[rates]': 'true',
    'populate[language]': 'true',
    'populate[durations]': 'true',
    'populate[expert_verifications]': 'true',
    'populate[service_area_selections]': 'true',
    'populate[audio_intro]': 'true',
    'populate[host_profile_images][populate][image]': 'true',
  };

  static const _singleRow = <String, dynamic>{
    'pagination[page]': '1',
    'pagination[pageSize]': '1',
  };

  /// Only what this lookup is proven to accept here: extra populate keys
  /// (gallery, categories, service areas) return "400 Invalid key".
  static const _callbackPopulate = <String, dynamic>{
    'populate[rates]': 'true',
    'populate[user][populate][profilePic]': 'true',
    'pagination[pageSize]': '1',
  };

  static const _unavailable = ApiException(
    ApiErrorType.rejected,
    messageKey: 'listing:errors.profile_unavailable',
  );

  /// Host listing with extra Strapi params in [query] (flat bracket keys,
  /// e.g. `{'filters[isActive][\$eq]': 'true'}`).
  static Future<List<HostCard>> fetchHosts({
    Map<String, dynamic> query = const {},
  }) async {
    final body = await ApiClient.get(
      '/expert-profiles',
      query: {
        'populate[user][populate]': 'profilePic',
        'populate[service_area_selections]': 'true',
        ...query,
      },
    );
    final rows = Strapi.list(body);
    return [
      for (var i = 0; i < rows.length; i++)
        HostCard.fromJson(rows[i], index: i),
    ];
  }

  /// Full profile for a search hit: by expert-profile documentId (what
  /// `/search` carries), then user documentId, then handler. One of the two
  /// ids is required; [handler] is only the last rung.
  static Future<HostCard> findHost({
    String? expertDocumentId,
    String? userDocumentId,
    String? handler,
  }) async {
    final expertId = expertDocumentId?.trim() ?? '';
    final userId = userDocumentId?.trim() ?? '';
    if (expertId.isEmpty && userId.isEmpty) throw _unavailable;
    const query = {...hostCardPopulate, ..._singleRow};

    JsonMap? row;
    if (expertId.isNotEmpty) {
      row = _first(await _rows({r'filters[documentId][$eq]': expertId}, query));
    }
    if (row == null && userId.isNotEmpty) {
      row = _first(
        await _rows({r'filters[user][documentId][$eq]': userId}, query),
      );
    }
    if (row == null && (handler ?? '').isNotEmpty) {
      row = _first(await _rows({r'filters[handler][$eq]': handler}, query));
    }
    final host = HostCard.fromJson(row);
    if (host.documentId == null && host.userDocumentId == null) {
      throw _unavailable;
    }
    return host;
  }

  /// Profile behind a shared link / `openUserId`: [targetId] may be a user
  /// documentId, an expert-profile documentId or a handler. Only an approved
  /// host opens, so a link cannot reach a profile a tap never could — except
  /// the viewer's own ([isOwnProfile]).
  static Future<HostCard> findHostByLink(
    String targetId, {
    bool isOwnProfile = false,
  }) async {
    final target = targetId.trim();
    if (target.isEmpty) throw _unavailable;
    const query = {
      ...hostCardPopulate,
      'populate[expert_profile_approvals]': 'true',
      ..._singleRow,
    };

    final lower = target.toLowerCase();
    bool isTarget(JsonMap row) {
      final user = Strapi.map(row['user']) ?? const {};
      return (J.str(row['handler']) ?? '').toLowerCase() == lower ||
          (J.str(row['documentId']) ?? '').toLowerCase() == lower ||
          (J.str(user['documentId']) ?? '').toLowerCase() == lower;
    }

    JsonMap? row;
    for (final filter in [
      {r'filters[user][documentId][$eq]': target},
      {r'filters[documentId][$eq]': target},
      {r'filters[handler][$eq]': target},
    ]) {
      row = (await _rows(filter, query)).where(isTarget).firstOrNull;
      if (row != null) break;
    }
    if (row == null) throw _unavailable;

    final host = HostCard.fromJson(row);
    if (!isOwnProfile && !host.isApprovedHost) throw _unavailable;
    if (host.userDocumentId == null &&
        host.documentId == null &&
        host.receiverId == null) {
      throw _unavailable;
    }
    return host;
  }

  /// Host of a "call me back" nudge (`PING_CLIENT` push): by expert-profile
  /// documentId, then by user id. The push carries no prices, so callers
  /// read [HostCard.aPrice] / [HostCard.vPrice] here and fall back to the
  /// push values when this fails.
  static Future<HostCard> findCallbackHost({
    String? expertDocumentId,
    String? userId,
  }) async {
    JsonMap? row;
    if ((expertDocumentId ?? '').isNotEmpty) {
      row = _first(
        await _rows({
          r'filters[documentId][$eq]': expertDocumentId,
        }, _callbackPopulate),
      );
    }
    if (row == null && (userId ?? '').isNotEmpty) {
      row = _first(
        await _rows({r'filters[user][id][$eq]': userId}, _callbackPopulate),
      );
    }
    if (row == null) throw _unavailable;
    return HostCard.fromJson(row);
  }

  static Future<List<JsonMap>> _rows(
    Map<String, dynamic> filter,
    Map<String, dynamic> query,
  ) async => Strapi.list(
    await ApiClient.get('/expert-profiles', query: {...filter, ...query}),
  );

  static JsonMap? _first(List<JsonMap> rows) => rows.firstOrNull;
}
