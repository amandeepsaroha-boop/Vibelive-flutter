import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/profile_models.dart';
import 'host_page.dart';

/// One moderation notice. [body] is an i18n key unless [note] (the
/// moderator's own words) is set.
typedef HostModerationNotice = ({
  HostTone tone,
  String title,
  Map<String, dynamic>? vars,
  String? body,
  String? note,
});

/// RN `getModerationBanners`: rejected changes (with the note), text
/// changes awaiting review, photos rejected / awaiting review, the audio
/// intro's state.
List<HostModerationNotice> hostModerationNotices(HostProfile host) {
  final out = <HostModerationNotice>[];
  final status = host.moderationStatus;
  final note = (host.moderationNote ?? '').trim();
  final pending = host.raw['pending_changes'];
  if (status == 'rejected' && note.isNotEmpty) {
    out.add((
      tone: HostTone.danger,
      title: 'hostflow:moderation.rejected',
      vars: null,
      body: null,
      note: note,
    ));
  } else if (status == 'pending_review' && pending != null) {
    final fields = host.pendingChangeFields;
    out.add((
      tone: HostTone.warning,
      title: 'hostflow:moderation.pending',
      vars: {'fields': fields},
      body: fields.isEmpty
          ? 'hostflow:moderation.pending_body'
          : 'hostflow:moderation.pending_fields',
      note: null,
    ));
  }
  final rows = [
    for (final row
        in host.raw['host_profile_images'] is List
            ? host.raw['host_profile_images'] as List
            : const [])
      if (row is Map) row,
  ];
  final rejected = rows.where((r) => r['status_enum'] == 'rejected').length;
  final waiting = rows
      .where((r) => (r['status_enum'] ?? 'pending') == 'pending')
      .length;
  if (rejected > 0) {
    out.add((
      tone: HostTone.danger,
      title: 'hostflow:moderation.photos_rejected',
      vars: {'count': rejected},
      body: 'hostflow:moderation.photos_rejected_body',
      note: null,
    ));
  }
  if (waiting > 0) {
    out.add((
      tone: HostTone.warning,
      title: 'hostflow:moderation.photos_pending',
      vars: {'count': waiting},
      body: 'hostflow:moderation.photos_pending_body',
      note: null,
    ));
  }
  final audio = host.audioIntroStatus;
  if (audio == 'rejected') {
    out.add((
      tone: HostTone.danger,
      title: 'hostflow:moderation.audio_rejected',
      vars: null,
      body: 'hostflow:moderation.audio_rejected_body',
      note: null,
    ));
  } else if (audio == 'pending' && host.audioIntro != null) {
    out.add((
      tone: HostTone.warning,
      title: 'hostflow:moderation.audio_pending',
      vars: null,
      body: 'hostflow:moderation.audio_pending_body',
      note: null,
    ));
  }
  return out;
}

/// The notices as stacked cards; nothing when there is no news.
class HostModerationBanners extends StatelessWidget {
  const HostModerationBanners({super.key, required this.host});
  final HostProfile host;

  /// Fields with a friendly name (RN: tagline, about, handle, website).
  static const _known = {'tagline', 'descriptions', 'handler', 'website'};

  @override
  Widget build(BuildContext context) {
    final notices = hostModerationNotices(host);
    if (notices.isEmpty) return const SizedBox.shrink();
    String fieldNames(Map<String, dynamic>? vars) => [
      for (final f in (vars?['fields'] as List? ?? const []))
        _known.contains(f) ? context.t('hostflow:moderation.field.$f') : '$f',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in notices)
          Padding(
            padding: EdgeInsets.only(bottom: 10.ms),
            child: HostToneCard(
              tone: n.tone,
              icon: n.tone == HostTone.danger
                  ? LucideIcons.circleAlert
                  : LucideIcons.clock3,
              title: n.title,
              titleVariables: n.vars,
              message:
                  n.note ??
                  context.t(n.body!, variables: {'fields': fieldNames(n.vars)}),
              translateMessage: false,
            ),
          ),
      ],
    );
  }
}
