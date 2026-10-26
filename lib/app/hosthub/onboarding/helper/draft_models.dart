import 'package:flutter/foundation.dart';

import '../../../../core/network/strapi.dart';
import '../../../api/hosthub/catalog_models.dart';
import '../../../api/hosthub/profile_models.dart';

/// A topic of the interests form's topic question (option value + label).
@immutable
class HostTopic {
  const HostTopic({required this.value, required this.label, this.emoji = ''});

  factory HostTopic.fromJson(Map json) => HostTopic(
    value: '${json['value'] ?? ''}',
    label: '${json['label'] ?? ''}',
    emoji: '${json['emoji'] ?? ''}',
  );

  final String value;
  final String label;
  final String emoji;

  JsonMap toJson() => {'value': value, 'label': label, 'emoji': emoji};

  @override
  bool operator ==(Object other) => other is HostTopic && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// One photo slot. [mediaId] is set once the upload finished; [localPath]
/// is the picked file (preview while it uploads).
@immutable
class HostDraftPhoto {
  const HostDraftPhoto({
    required this.key,
    this.mediaId,
    this.url,
    this.localPath,
    this.failed = false,
  });

  factory HostDraftPhoto.fromJson(Map json) => HostDraftPhoto(
    key: '${json['key'] ?? json['mediaId'] ?? ''}',
    mediaId: json['mediaId'],
    url: J.str(json['url']),
    localPath: J.str(json['localPath']),
  );

  /// Stable identity for the tile (survives the upload finishing).
  final String key;
  final Object? mediaId;
  final String? url;
  final String? localPath;

  /// The upload failed; tapping the tile retries.
  final bool failed;

  bool get uploaded => mediaId != null;
  bool get uploading => mediaId == null && !failed;

  HostDraftPhoto copyWith({Object? mediaId, String? url, bool? failed}) =>
      HostDraftPhoto(
        key: key,
        mediaId: mediaId ?? this.mediaId,
        url: url ?? this.url,
        localPath: localPath,
        failed: failed ?? this.failed,
      );

  /// Only uploaded photos are kept: a picked file in the OS temp folder may
  /// be gone by the next launch.
  JsonMap? toJson() => mediaId == null
      ? null
      : {'key': key, 'mediaId': mediaId, 'url': url, 'localPath': localPath};
}

/// One time slot of a day, minutes since midnight.
@immutable
class HostSlot {
  const HostSlot(this.start, this.end);

  static HostSlot? fromJson(dynamic json) {
    if (json is! Map) return null;
    final start = J.integer(json['start']);
    final end = J.integer(json['end']);
    return start == null || end == null ? null : HostSlot(start, end);
  }

  final int start;
  final int end;

  /// RN ScheduleScreen `isOverlapping`: touching slots do not overlap.
  bool overlaps(HostSlot other) => start < other.end && other.start < end;

  JsonMap toJson() => {'start': start, 'end': end};

  @override
  bool operator ==(Object other) =>
      other is HostSlot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// One day of the weekly schedule: on/off and its slots, sorted by start
/// (RN ScheduleScreen). A day that is off has no slots.
@immutable
class HostDaySlot {
  const HostDaySlot({
    required this.enabled,
    List<HostSlot> slots = const [defaultSlot],
  }) : _slots = slots;

  /// 6:00 PM – 12:00 AM, the design's default.
  static const defaultStart = 18 * 60;
  static const defaultEnd = endOfDay;
  static const defaultSlot = HostSlot(defaultStart, defaultEnd);

  /// A slot added with "Add slot" (RN: 9:00 AM, one hour).
  static const newSlotStart = 9 * 60;
  static const newSlotMinutes = 60;

  /// "12:00 AM" as an end time. The backend wants end > start on the same
  /// day (RN rule), so midnight is stored as 23:59.
  static const endOfDay = 23 * 60 + 59;

  /// RN minimum slot length.
  static const minSlotMinutes = 30;

  /// Reads `{enabled, slots: [{start, end}]}`, and the older single-slot
  /// `{enabled, start, end}` drafts.
  factory HostDaySlot.fromJson(Map json) {
    final enabled = json['enabled'] == true;
    final saved = json['slots'];
    final slots = saved is List
        ? [for (final s in saved) ?HostSlot.fromJson(s)]
        : [
            HostSlot(
              J.integer(json['start']) ?? defaultStart,
              J.integer(json['end']) ?? defaultEnd,
            ),
          ];
    return enabled && slots.isNotEmpty
        ? HostDaySlot(enabled: true, slots: sorted(slots))
        : const HostDaySlot(enabled: false);
  }

  final bool enabled;
  final List<HostSlot> _slots;

  List<HostSlot> get slots => enabled ? _slots : const [];

  /// RN `toggleDay`: off clears the slots; on starts with the default slot.
  HostDaySlot toggled(bool on) =>
      on ? (enabled ? this : const HostDaySlot(enabled: true)) : off;

  static const off = HostDaySlot(enabled: false, slots: []);

  /// RN `addSlot` rules for [slot] against the day's other slots (all but
  /// [replacing]): the `hostflow:errors.*` key, or null when it is fine.
  String? check(HostSlot slot, {int? replacing}) {
    if (slot.end <= slot.start) return 'slot_order';
    if (slot.end - slot.start < minSlotMinutes) return 'slot_short';
    for (var i = 0; i < slots.length; i++) {
      if (i != replacing && slots[i].overlaps(slot)) return 'slot_overlap';
    }
    return null;
  }

  /// Adds [slot] (or replaces the one at [replacing]), sorted by start.
  HostDaySlot withSlot(HostSlot slot, {int? replacing}) => HostDaySlot(
    enabled: true,
    slots: sorted([
      for (var i = 0; i < slots.length; i++)
        if (i != replacing) slots[i],
      slot,
    ]),
  );

  /// RN `removeSlot`: the last slot gone turns the day off.
  HostDaySlot withoutSlot(int index) {
    final rest = [...slots]..removeAt(index);
    return rest.isEmpty ? off : HostDaySlot(enabled: true, slots: rest);
  }

  /// Where "Add slot" opens: 9:00 – 10:00 AM (RN), or after the day's last
  /// slot when that hour is taken.
  HostSlot get nextSlot {
    const first = HostSlot(newSlotStart, newSlotStart + newSlotMinutes);
    if (!slots.any(first.overlaps)) return first;
    final s = slots.last.end.clamp(0, 23 * 60);
    return HostSlot(s, (s + newSlotMinutes).clamp(0, endOfDay));
  }

  static List<HostSlot> sorted(List<HostSlot> slots) =>
      [...slots]..sort((a, b) => a.start.compareTo(b.start));

  JsonMap toJson() => {
    'enabled': enabled,
    'slots': [for (final s in slots) s.toJson()],
  };

  /// Mon–Fri on, weekend off (the design's default week).
  static Map<HostWeekday, HostDaySlot> defaultWeek() => {
    for (final d in HostWeekday.values)
      d: d != HostWeekday.saturday && d != HostWeekday.sunday
          ? const HostDaySlot(enabled: true)
          : off,
  };

  @override
  bool operator ==(Object other) =>
      other is HostDaySlot &&
      other.enabled == enabled &&
      listEquals(other.slots, slots);

  @override
  int get hashCode => Object.hash(enabled, Object.hashAll(slots));
}

/// JSON helpers for the option types the draft keeps.
abstract final class DraftJson {
  static JsonMap language(HostOption o) => {
    'id': o.id,
    'documentId': o.documentId,
    'label': o.label,
  };

  static HostOption? languageFrom(dynamic json) {
    if (json is! Map) return null;
    final label = J.str(json['label']) ?? '';
    final option = HostOption(
      id: J.integer(json['id']),
      documentId: J.str(json['documentId']),
      label: label,
      raw: {
        if (json['id'] != null) 'id': json['id'],
        if (json['documentId'] != null) 'documentId': json['documentId'],
        'name': label,
      },
    );
    return option.value == null || label.isEmpty ? null : option;
  }
}
