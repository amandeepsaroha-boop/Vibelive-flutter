import '../../../api/listingflow/listing_models.dart';
import 'draft_controller.dart';

/// The draft as the client profile sheet's [HostCard], built from the same
/// expert-row shape the server sends, so the preview renders through the
/// real profile widgets. A new host has no rating, no reviews and no
/// verification or influencer badge yet; none are invented here.
HostCard previewHostCard(HostDraftController d) {
  final photos = [
    for (final p in d.photos.value)
      if (p.url != null) p,
  ];
  // The new recording on this phone, else the saved one: the preview plays
  // the voice intro as clients will hear it.
  final voice = d.voiceIntro.value;
  final voiceUrl = switch (voice?.path) {
    final path? => Uri.file(path).toString(),
    _ => voice?.savedUrl,
  };
  final rates = (
    voice: d.audioOn.value ? d.audioRate.value : 0,
    video: d.videoOn.value ? d.videoRate.value : 0,
  );
  return HostCard.fromJson({
    'id': 0,
    'documentId': d.expertId ?? 'preview',
    'handler': d.handle.text.trim(),
    'tagline': d.tagline.text.trim(),
    'descriptions': d.bio.text.trim(),
    'isActive': d.availableNow.value && !d.vacation.value,
    'rates': {'voiceCallRate': rates.voice, 'videoCallRate': rates.video},
    'language': [
      for (final l in d.languages.value) {'name': l.label},
    ],
    'service_area_selections': [
      for (final t in d.topics.value)
        {
          'snapshot': {
            'question': {'key': SupportTopicKey.question},
            'option': {'label': t.label, 'value': t.value},
          },
        },
    ],
    // Only uploaded photos have a URL; the sheet shows approved ones.
    'host_profile_images': [
      for (final (i, p) in photos.indexed)
        {
          'priority': i + 1,
          'isprimary': i == 0,
          'status_enum': 'approved',
          'image': {'url': p.url},
        },
    ],
    if (voiceUrl != null) ...{
      'audio_intro': {'url': voiceUrl},
      'audio_intro_status': 'approved',
    },
    'user': {
      'name': d.name.text.trim(),
      'district': {'name': d.district.value?.name ?? ''},
    },
  });
}
