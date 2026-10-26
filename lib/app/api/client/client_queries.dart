import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/session/session_store.dart';
import '../callscreen/call_keys.dart';
import '../homescreen/home_keys.dart';
import '../listingflow/listing_keys.dart';
import 'block_api.dart';
import 'client_keys.dart';
import 'client_models.dart';
import 'favorite_api.dart';
import 'geo_api.dart';
import 'gst_api.dart';
import 'profile_api.dart';
import 'referral_api.dart';

// ── My profile ───────────────────────────────────────────────────────────

/// The signed-in user with their expert profile. Kept on disk (renders
/// instantly on launch) and mirrored into [SessionStore] whenever it loads.
QueryResult<UserWithExpert, ApiException> useMyProfile(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final id = _useUserId(userDocumentId);
  return usePersistedQuery<UserWithExpert>(
    ClientKeys.myProfile(id ?? ''),
    () => _fetchMyProfile(id!),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
    toJson: (p) => p.toJson(),
    fromJson: UserWithExpert.fromJson,
  );
}

/// Outside widgets (prime after login, push handlers). Pass
/// `staleDuration: StaleTime.none` to force a refetch.
Future<UserWithExpert> ensureMyProfile(
  String userDocumentId, {
  Duration staleDuration = StaleTime.short,
}) {
  final key = ClientKeys.myProfile(userDocumentId);
  return queryCache.fetchQuery<UserWithExpert>(key, () async {
    final profile = await _fetchMyProfile(userDocumentId);
    QueryPersist.write(key, profile.toJson());
    return profile;
  }, staleDuration: staleDuration);
}

Future<UserWithExpert> _fetchMyProfile(String userDocumentId) async {
  final profile = await ProfileApi.fetchUserWithExpert(userDocumentId);
  await syncSessionWithProfile(userDocumentId, profile);
  return profile;
}

/// Copies a fresh profile into [SessionStore] (RN refreshed the auth store
/// from the cached profile), only while that user is still signed in and only
/// when something changed.
Future<void> syncSessionWithProfile(
  String userDocumentId,
  UserWithExpert profile,
) async {
  final store = SessionStore.instance;
  final session = store.value;
  if (session.userDocumentId != userDocumentId) return;
  if (jsonEncode({...?session.user, ...profile.user}) !=
      jsonEncode(session.user)) {
    await store.updateUser(profile.user);
  }
  if (jsonEncode(profile.expert) != jsonEncode(store.value.expert)) {
    await store.updateExpert(profile.expert);
  }
}

/// Someone else's user + expert record (call history, call setup…).
QueryResult<UserWithExpert, ApiException> useUserWithExpert(
  BuildContext context,
  String? userDocumentId, {
  bool enabled = true,
}) {
  final id = userDocumentId ?? '';
  return useApiQuery<UserWithExpert>(
    ClientKeys.userWithExpert(id),
    () => ProfileApi.fetchUserWithExpert(id),
    context: context,
    enabled: enabled && id.isNotEmpty,
    staleDuration: StaleTime.medium,
  );
}

Future<UserWithExpert> ensureUserWithExpert(String userDocumentId) =>
    queryCache.fetchQuery<UserWithExpert>(
      ClientKeys.userWithExpert(userDocumentId),
      () => ProfileApi.fetchUserWithExpert(userDocumentId),
      staleDuration: StaleTime.medium,
    );

/// Personal Info save. The profile refetch it triggers updates the session.
MutationResult<void, ApiException, PersonalInfoInput> useUpdatePersonalInfo({
  String? userDocumentId,
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, PersonalInfoInput>(
  (input) async {
    final id = _requireUserId(input.current.documentId ?? userDocumentId);
    GeoOption? country;
    try {
      country = await ensureCountryByName(GeoApi.defaultCountry);
    } on ApiException {
      // Deliberate (RN): the country relation is optional, never block a save.
      country = null;
    }
    await ProfileApi.updatePersonalInfo(id, input, country: country);
  },
  // The own card (profile sheet, listings) shows the name and photo too.
  invalidates: const [ClientKeys.profiles, ListingKeys.all],
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);

/// Upload a local image and make it the profile photo. [upload] replaces the
/// Strapi media upload (a device seam faked in tests); it returns the media.
MutationResult<JsonMap, ApiException, String> useUpdateProfilePhoto({
  String? userDocumentId,
  Future<JsonMap> Function(String filePath)? upload,
  void Function(JsonMap file)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<JsonMap, String>(
  (filePath) async {
    final id = _requireUserId(userDocumentId);
    if (upload == null) return ProfileApi.updateProfilePhoto(id, filePath);
    final file = await upload(filePath);
    await ProfileApi.setProfilePhoto(id, file['id']);
    return file;
  },
  // The own card (profile sheet, listings) shows the name and photo too.
  invalidates: const [ClientKeys.profiles, ListingKeys.all],
  onSuccess: (file, _) => onSuccess?.call(file),
  onError: (e, _) => onError?.call(e),
);

// ── Geo ──────────────────────────────────────────────────────────────────

QueryResult<List<GeoOption>, ApiException> useCountries(
  BuildContext context, {
  String search = '',
  int page = 1,
  int pageSize = 25,
  bool enabled = true,
}) {
  final term = search.trim();
  return useApiQuery<List<GeoOption>>(
    ClientKeys.countries(search: term, page: page, pageSize: pageSize),
    () => GeoApi.fetchCountries(search: term, page: page, pageSize: pageSize),
    context: context,
    enabled: enabled,
    staleDuration: StaleTime.static,
  );
}

/// Null when no country has that name.
Future<GeoOption?> ensureCountryByName(String name) =>
    queryCache.fetchQuery<GeoOption?>(
      ClientKeys.countryByName(name),
      () => GeoApi.findCountryByName(name),
      staleDuration: StaleTime.static,
    );

/// Every state (one page): current-location autofill matches against them.
Future<List<GeoOption>> ensureAllStates() => queryCache.fetchQuery(
  ClientKeys.states(
    countryName: GeoApi.defaultCountry,
    search: '',
    page: 1,
    pageSize: 100,
  ),
  () => GeoApi.fetchStates(pageSize: 100),
  staleDuration: StaleTime.static,
);

/// Every district of [state] (the largest state has 75).
Future<List<GeoOption>> ensureAllDistricts(GeoOption state) {
  final stateId = state.filterId ?? '';
  return queryCache.fetchQuery(
    ClientKeys.districts(
      stateId: stateId,
      stateIdField: state.filterField.name,
      search: '',
      page: 1,
      pageSize: 100,
    ),
    () => GeoApi.fetchDistricts(
      stateId: stateId,
      field: state.filterField,
      pageSize: 100,
    ),
    staleDuration: StaleTime.static,
  );
}

QueryResult<List<GeoOption>, ApiException> useStates(
  BuildContext context, {
  String search = '',
  String? countryName = GeoApi.defaultCountry,
  int page = 1,
  int pageSize = 45,
  bool enabled = true,
}) {
  final term = search.trim();
  return useApiQuery<List<GeoOption>>(
    ClientKeys.states(
      countryName: countryName,
      search: term,
      page: page,
      pageSize: pageSize,
    ),
    () => GeoApi.fetchStates(
      search: term,
      countryName: countryName,
      page: page,
      pageSize: pageSize,
    ),
    context: context,
    enabled: enabled,
    staleDuration: StaleTime.static,
  );
}

/// Districts of [state]; disabled until a state is picked.
QueryResult<List<GeoOption>, ApiException> useDistricts(
  BuildContext context, {
  required GeoOption? state,
  String search = '',
  int page = 1,
  int pageSize = 45,
  bool enabled = true,
}) {
  final term = search.trim();
  final stateId = state?.filterId ?? '';
  final field = state?.filterField ?? GeoIdField.documentId;
  return useApiQuery<List<GeoOption>>(
    ClientKeys.districts(
      stateId: stateId,
      stateIdField: field.name,
      search: term,
      page: page,
      pageSize: pageSize,
    ),
    () => GeoApi.fetchDistricts(
      stateId: stateId,
      field: field,
      search: term,
      page: page,
      pageSize: pageSize,
    ),
    context: context,
    enabled: enabled && stateId.isNotEmpty,
    staleDuration: StaleTime.static,
  );
}

// ── Blocked users ────────────────────────────────────────────────────────

QueryResult<List<BlockedUser>, ApiException> useBlockedUsers(
  BuildContext context, {
  int limit = 50,
  int offset = 0,
  bool enabled = true,
}) {
  final id = _useUserId(null);
  return useApiQuery<List<BlockedUser>>(
    ClientKeys.blockedUsersPage(id ?? '', limit: limit, offset: offset),
    () => BlockApi.fetchBlockedUsers(limit: limit, offset: offset),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

/// Block from a profile, the feedback sheet or a call. RN wiped every cached
/// list afterwards so the person vanished from feeds and search: pass those
/// features' keys (home feed, search, call history…) in [invalidates].
MutationResult<void, ApiException, BlockUserInput> useBlockUser({
  List<RawQueryKey> invalidates = const [],
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, BlockUserInput>(
  BlockApi.blockUser,
  invalidates: [..._afterBlockChange, ...invalidates],
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);

/// Variables: [BlockedUser.targetUserId]. See [useBlockUser] for
/// [invalidates].
MutationResult<void, ApiException, String> useUnblockUser({
  List<RawQueryKey> invalidates = const [],
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, String>(
  BlockApi.unblockUser,
  invalidates: [..._afterBlockChange, ...invalidates],
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);

/// A block hides the user from every list (RN refetched all of them).
const _afterBlockChange = <RawQueryKey>[
  ClientKeys.blockedUsers,
  ClientKeys.favorites,
  HomeKeys.all,
  ListingKeys.all,
  CallKeys.history,
];

// ── Favourites ───────────────────────────────────────────────────────────

QueryResult<List<FavoriteExpert>, ApiException> useFavorites(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final id = _useUserId(userDocumentId);
  return useApiQuery<List<FavoriteExpert>>(
    ClientKeys.favoritesOf(id ?? ''),
    () => FavoriteApi.fetchFavorites(id!),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

/// Variables: the expert profile documentId.
MutationResult<FavoriteExpert, ApiException, String> useAddFavorite({
  String? userDocumentId,
  void Function(FavoriteExpert favorite)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<FavoriteExpert, String>(
  (expertDocumentId) => FavoriteApi.addFavorite(
    userDocumentId: _requireUserId(userDocumentId),
    expertDocumentId: expertDocumentId.trim(),
  ),
  invalidates: const [ClientKeys.favorites],
  onSuccess: (favorite, _) => onSuccess?.call(favorite),
  onError: (e, _) => onError?.call(e),
);

MutationResult<void, ApiException, FavoriteExpert> useRemoveFavorite({
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, FavoriteExpert>(
  (favorite) => FavoriteApi.removeFavorite(
    favoriteId: favorite.id,
    expertId: favorite.expertId,
  ),
  invalidates: const [ClientKeys.favorites],
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);

// ── GST ──────────────────────────────────────────────────────────────────

QueryResult<GstDetails, ApiException> useGstDetails(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final id = _useUserId(userDocumentId);
  return useApiQuery<GstDetails>(
    ClientKeys.gstDetailsOf(id ?? ''),
    () async => GstDetails.fromUser(await _menuRelations(id!)),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

/// Returns the saved row. Pass [GstDetails.documentId] as
/// `GstDetailsInput.gstDetailId` when editing.
MutationResult<JsonMap?, ApiException, GstDetailsInput> useSaveGstDetails({
  String? userDocumentId,
  void Function(JsonMap? saved)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<JsonMap?, GstDetailsInput>(
  (input) => GstApi.saveGstDetails(_requireUserId(userDocumentId), input),
  invalidates: const [ClientKeys.menuRelations, ClientKeys.gstDetails],
  onSuccess: (saved, _) => onSuccess?.call(saved),
  onError: (e, _) => onError?.call(e),
);

// ── Referral ─────────────────────────────────────────────────────────────

QueryResult<ReferralDashboard, ApiException> useReferralDashboard(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final id = _useUserId(userDocumentId);
  return useApiQuery<ReferralDashboard>(
    ClientKeys.referralDashboard(id ?? ''),
    () async => ReferralApi.dashboardFor(await _menuRelations(id!)),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

/// Fresh dashboard outside the hook (refresh button, pull-to-refresh). Lands
/// in the [useReferralDashboard] cache; throws so the caller can tell.
Future<ReferralDashboard> ensureReferralDashboard({
  String? userDocumentId,
  Duration staleDuration = StaleTime.none,
}) {
  final id = _requireUserId(userDocumentId);
  return queryCache.fetchQuery<ReferralDashboard>(
    ClientKeys.referralDashboard(id),
    () async => ReferralApi.dashboardFor(
      await _menuRelations(id, staleDuration: staleDuration),
    ),
    staleDuration: staleDuration,
  );
}

/// After a share (RN): the counter the backend sent, else one more.
void bumpReferralClicks(int? count, {String? userDocumentId}) {
  final id = _requireUserId(userDocumentId);
  final key = ClientKeys.referralDashboard(id);
  final old = queryCache.getQueryData<ReferralDashboard, ApiException>(key);
  if (old == null) return;
  queryCache.setQueryData<ReferralDashboard, ApiException>(
    key,
    (_) => old.withClicks(count ?? old.totalClicks + 1),
  );
}

/// '' when the user has no code (hide the invite card).
QueryResult<String, ApiException> useReferralCode(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final id = _useUserId(userDocumentId);
  return useApiQuery<String>(
    ClientKeys.referralCode(id ?? ''),
    () async => ReferralDashboard.codeFrom(await _menuRelations(id!)),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.medium,
  );
}

/// Count a share of a referral code (variables: the code). Best effort: fire
/// it after the share sheet and ignore failures, like RN.
MutationResult<int?, ApiException, String> useTrackReferralShare({
  required ReferralShareType type,
  void Function(int? count)? onSuccess,
}) => useApiMutation<int?, String>(
  (code) => ReferralApi.trackShare(code, type),
  invalidates: const [ClientKeys.menuRelations, ClientKeys.referral],
  onSuccess: (count, _) => onSuccess?.call(count),
);

// ── Helpers ──────────────────────────────────────────────────────────────

/// The user with referral + GST relations: one cached read behind the
/// invite card, Referral and GST (each used to send its own). Writes list
/// [ClientKeys.menuRelations] FIRST in `invalidates`: invalidating a screen's
/// key refetches it at once, and that must not reuse this read.
Future<JsonMap?> _menuRelations(
  String userDocumentId, {
  Duration staleDuration = StaleTime.short,
}) => queryCache.fetchQuery<JsonMap?>(
  ClientKeys.menuRelationsOf(userDocumentId),
  () => ProfileApi.fetchUserWithMenuRelations(userDocumentId),
  staleDuration: staleDuration,
);

/// [override], else the signed-in user (rebuilds when the session changes).
String? _useUserId(String? override) {
  final session = useValueListenable(SessionStore.instance);
  final id = override ?? session.userDocumentId;
  return (id == null || id.isEmpty) ? null : id;
}

String _requireUserId(String? override) {
  final id = override ?? SessionStore.instance.value.userDocumentId;
  if (id == null || id.isEmpty) {
    throw const ApiException(
      ApiErrorType.rejected,
      messageKey: 'client:errors.no_session',
    );
  }
  return id;
}
