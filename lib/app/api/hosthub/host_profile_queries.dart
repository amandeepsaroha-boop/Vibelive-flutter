part of 'hosthub_queries.dart';

// ── Host profile ────────────────────────────────────────────────────────────

/// A host profile by id; defaults to the signed-in host's. Null when it
/// cannot be found (even through the 404 fallbacks).
QueryResult<HostProfile?, ApiException> useHostProfile(
  BuildContext context, {
  String? expertId,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = expertId ?? _ownExpertId(session);
  return useApiQuery<HostProfile?>(
    HostHubKeys.profile(id ?? ''),
    () => HostProfileApi.fetchById(
      id!,
      ownerUserDocumentId: session.userDocumentId,
    ),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

/// The host profile owned by a user; defaults to the signed-in user. Null
/// for a non-host.
QueryResult<HostProfile?, ApiException> useHostProfileByUser(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = userDocumentId ?? session.userDocumentId;
  return useApiQuery<HostProfile?>(
    HostHubKeys.profileByUser(id ?? ''),
    () => HostProfileApi.fetchByUser(id!),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

Future<HostProfile?> ensureHostProfile(String expertId) =>
    queryCache.fetchQuery<HostProfile?>(
      HostHubKeys.profile(expertId),
      () => HostProfileApi.fetchById(
        expertId,
        ownerUserDocumentId: SessionStore.instance.value.userDocumentId,
      ),
    );

/// Completion including the expertise check (RN `getExpertProfileCompletion`).
Future<HostProfileCompletion> checkHostProfileCompletion(
  HostProfile profile,
) async {
  ExpertiseSelections? expertise;
  try {
    expertise = await ensureMyExpertise();
  } on ApiException catch (e) {
    // RN counted an unreadable expertise snapshot as "not set" instead of
    // failing the whole check.
    Log.w('hosthub', 'expertise read failed: $e');
  }
  return profile.completionWith(expertise);
}

/// Saves a patch (rates, schedule, availability, categories…), then returns
/// the re-read profile. [alsoInvalidate]: other features' keys showing the
/// expert (e.g. the client "my profile" query).
MutationResult<HostProfile?, ApiException, HostProfileUpdate>
useUpdateHostProfile({
  List<RawQueryKey> alsoInvalidate = const [],
  void Function(HostProfile? profile)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<HostProfile?, HostProfileUpdate>(
  _updateHostProfile,
  invalidates: [HostHubKeys.profileAll, ListingKeys.all, ...alsoInvalidate],
  onSuccess: (profile, _) => onSuccess?.call(profile),
  onError: (e, _) => onError?.call(e),
);

/// Professional Details: uploads new photos and the audio intro, creates or
/// updates the profile, then syncs the photo rows. The caller still updates
/// the user record (`profilePic`, `role`) via the client feature; see
/// [ProfessionalDetailsResult.photoMediaIds].
MutationResult<
  ProfessionalDetailsResult,
  ApiException,
  ProfessionalDetailsInput
>
useSaveProfessionalDetails({
  List<RawQueryKey> alsoInvalidate = const [],
  void Function(ProfessionalDetailsResult result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<ProfessionalDetailsResult, ProfessionalDetailsInput>(
  _saveProfessionalDetails,
  invalidates: [
    HostHubKeys.profileAll,
    ListingKeys.all,
    HostHubKeys.imagesAll,
    HostHubKeys.statsAll,
    ...alsoInvalidate,
  ],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);

/// "Go live": activates the profile, then tells the admins.
MutationResult<HostProfile?, ApiException, GoLiveInput> useGoLive({
  List<RawQueryKey> alsoInvalidate = const [],
  void Function(HostProfile? profile)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<HostProfile?, GoLiveInput>(
  _goLive,
  invalidates: [HostHubKeys.profileAll, ListingKeys.all, ...alsoInvalidate],
  onSuccess: (profile, _) => onSuccess?.call(profile),
  onError: (e, _) => onError?.call(e),
);

Future<HostProfile?> _updateHostProfile(HostProfileUpdate u) async {
  final saved = await HostProfileApi.update(u.expertId, u.patch.data);
  return _refreshOwnProfile(u.expertId, saved: saved, echo: u.patch.echo);
}

Future<ProfessionalDetailsResult> _saveProfessionalDetails(
  ProfessionalDetailsInput input,
) async {
  final photoIds = <Object?>[
    for (var i = 0; i < 3; i++)
      i < input.photos.length && input.photos[i] != null
          ? await _mediaId(input.photos[i]!)
          : null,
  ];
  final audio = input.audioIntro;
  final audioId = audio == null
      ? null
      : await _mediaId(
          audio is HostMediaFile && audio.mimeType == null
              ? HostMediaFile(
                  audio.path,
                  fileName:
                      audio.fileName ??
                      'audio-intro-${DateTime.now().millisecondsSinceEpoch}.m4a',
                  mimeType: 'audio/mp4',
                )
              : audio,
        );

  final patch = HostProfilePatch.professional(
    handler: input.handler,
    tagline: input.tagline,
    gender: input.gender,
    description: input.description,
    website: input.website,
    languages: input.languages,
    audioIntroMediaId: audioId,
  );

  final existingId = input.expertId;
  final HostProfile? saved;
  final String expertId;
  if (existingId == null) {
    final created = await HostProfileApi.create({
      ...patch.data,
      'user': input.userDocumentId,
    });
    saved = created;
    expertId = created.key;
  } else {
    saved = await HostProfileApi.update(existingId, patch.data);
    expertId = existingId;
  }

  await HostImagesApi.sync(
    expertId: expertId,
    slots: photoIds,
    existing: input.existingPhotos,
  );

  return ProfessionalDetailsResult(
    expertId: expertId,
    created: existingId == null,
    photoMediaIds: photoIds,
    profile: await _refreshOwnProfile(expertId, saved: saved, echo: patch.echo),
  );
}

Future<HostProfile?> _goLive(GoLiveInput input) async {
  final profile = await _updateHostProfile((
    expertId: input.expertId,
    patch: HostProfilePatch.goLive,
  ));
  try {
    await HostApprovalApi.notifyAdminOnboarded(
      expertId: input.expertId,
      expertName: input.name,
      expertEmail: input.email,
    );
  } on ApiException catch (e) {
    // CE parity only; the endpoint may not exist on every deployment.
    Log.w('hosthub', 'notify-admin failed: $e');
  }
  return profile;
}

Future<Object?> _mediaId(HostMediaRef ref) async => switch (ref) {
  HostMediaId(:final id) => id,
  HostMediaFile(:final path, :final fileName, :final mimeType) =>
    (await UploadApi.uploadFile(
      path,
      fileName: fileName,
      mimeType: mimeType,
    ))['id'],
};

/// Re-reads the saved profile and mirrors it into the session: RN pushed
/// every saved expert into the auth store, which the warn bar, the /me menu
/// and the badge prompt read. A failed re-read must not turn a completed save
/// into a failure, so it falls back to the session copy + what was saved.
Future<HostProfile?> _refreshOwnProfile(
  String expertId, {
  HostProfile? saved,
  JsonMap echo = const {},
}) async {
  final session = SessionStore.instance.value;
  HostProfile? fresh;
  try {
    fresh = await HostProfileApi.fetchById(
      expertId,
      ownerUserDocumentId: session.userDocumentId,
    );
  } on ApiException catch (e) {
    Log.w('hosthub', 'post-save re-read failed: $e');
  }
  final mine = HostProfile.sameRecord(session.expert, expertId)
      ? session.expert
      : null;
  fresh ??= HostProfile.merge([mine, saved?.raw, echo]);
  if (fresh != null &&
      session.isAuthenticated &&
      (session.expert == null || mine != null)) {
    await SessionStore.instance.updateExpert(fresh.raw);
  }
  return fresh;
}

/// [_refreshOwnProfile] for the signed-in host, when there is one.
Future<void> _refreshSessionExpert() async {
  final id = _ownExpertId(SessionStore.instance.value);
  if (id != null) await _refreshOwnProfile(id);
}

// ── Profile images ──────────────────────────────────────────────────────────

QueryResult<List<HostProfileImage>, ApiException> useHostProfileImages(
  BuildContext context, {
  String? expertId,
  bool enabled = true,
}) {
  final session = useValueListenable(SessionStore.instance);
  final id = expertId ?? _ownExpertId(session);
  return useApiQuery<List<HostProfileImage>>(
    HostHubKeys.profileImages(id ?? ''),
    () => HostImagesApi.fetchAll(id!),
    context: context,
    enabled: enabled && id != null,
    staleDuration: StaleTime.short,
  );
}

/// Reorder/replace photos without the rest of Professional Details. The
/// caller still sets the user's `profilePic` to `slots.first` (client).
MutationResult<void, ApiException, HostImagesSync> useSyncHostProfileImages({
  List<RawQueryKey> alsoInvalidate = const [],
  void Function()? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<void, HostImagesSync>(
  (v) => HostImagesApi.sync(
    expertId: v.expertId,
    slots: v.slots,
    existing: v.existing,
  ),
  invalidates: [
    HostHubKeys.imagesAll,
    HostHubKeys.profileAll,
    ListingKeys.all,
    ...alsoInvalidate,
  ],
  onSuccess: (_, _) => onSuccess?.call(),
  onError: (e, _) => onError?.call(e),
);
