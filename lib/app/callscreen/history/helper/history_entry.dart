import 'package:flutter/foundation.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/callscreen/call_models.dart';
import 'history_format.dart';

/// Status color family of a row (RN badge / call-type icon colors).
enum HistoryTone { ok, missed, warning }

/// What one call-log row shows, derived once per data change so rows only
/// read fields (RN explore `mapCall` + the per-row render logic).
@immutable
class HistoryEntry {
  const HistoryEntry._({
    required this.item,
    required this.key,
    required this.name,
    required this.avatarUrl,
    required this.counterpartId,
    required this.direction,
    required this.when,
    required this.clock,
    required this.minutes,
    required this.showPing,
  });

  factory HistoryEntry.of(
    CallHistoryItem item, {
    required int index,
    required Duration pingWindow,
    required DateTime now,
    required HistoryFormat format,
  }) {
    final call = item.call;
    final party = item.counterpart;
    final at = call.at;
    return HistoryEntry._(
      item: item,
      key: call.key.isEmpty ? '#$index' : call.key,
      name: J.str(party?.name?.trim()),
      avatarUrl: _avatarOf(party),
      counterpartId: party?.userKey,
      direction: item.direction,
      when: at == null ? null : format.when(at),
      clock: HistoryFormat.clock(call.durationSeconds),
      minutes: HistoryFormat.minutes(call.durationMinutes),
      showPing: item.canPing(window: pingWindow, now: now),
    );
  }

  /// Rows for [items], in order.
  static List<HistoryEntry> all(
    List<CallHistoryItem> items, {
    required Duration pingWindow,
    required DateTime now,
    required HistoryFormat format,
  }) => [
    for (var i = 0; i < items.length; i++)
      HistoryEntry.of(
        items[i],
        index: i,
        pingWindow: pingWindow,
        now: now,
        format: format,
      ),
  ];

  final CallHistoryItem item;

  /// Stable per call (list keys, pending state).
  final String key;

  /// The other person's name; null → "Unknown".
  final String? name;
  final String? avatarUrl;

  /// The other person's documentId (else numeric id): profile, ping, report.
  final String? counterpartId;
  final CallDirection direction;

  /// `3:05 PM • OCT 21, 2026`; null when the call has no date.
  final String? when;

  /// Talk time `m:ss`, else [minutes].
  final String? clock;
  final String? minutes;

  /// NUDGE: a client missed / declined this call within the ping window.
  final bool showPing;

  bool get isOutgoing => item.isOutgoing;
  bool get isVideo => item.call.isVideo;
  CallOutcome get outcome => item.outcome;

  /// Tapping the row (and "See Profile") opens the host profile.
  bool get isExpert => item.isExpert;

  /// The other person is a host: "Report this Host Profile".
  bool get isHostRole => item.counterpart?.isExpertRole ?? false;

  /// "Rate this Call" in the menu.
  bool get canRate => item.canRate;

  HistoryTone get tone => switch (direction) {
    CallDirection.missed => HistoryTone.missed,
    CallDirection.declined ||
    CallDirection.outgoingMissed => HistoryTone.warning,
    _ => HistoryTone.ok,
  };

  /// Photo of a `/public-users/:id` lookup (RN `profilePic(u)`).
  static String? avatarOfUser(JsonMap? user) =>
      user == null ? null : Strapi.mediaFromAsset(user['profilePic']);

  /// Avatar-sized rendition first: the row shows it at 62 pt.
  static String? _avatarOf(CallParty? party) {
    if (party == null) return null;
    final formats = Strapi.map(party.raw['profilePic'])?['formats'];
    String? format(String name) {
      final f = formats is Map ? formats[name] : null;
      return f is Map ? J.str(f['url']) : null;
    }

    return Strapi.mediaUrl(format('small') ?? format('thumbnail')) ??
        party.avatarUrl;
  }
}
