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

/// One day of the weekly schedule (a single slot, minutes since midnight).
@immutable
class HostDaySlot {
  const HostDaySlot({
    required this.enabled,
    this.start = defaultStart,
    this.end = defaultEnd,
  });

  /// 6:00 PM – 12:00 AM, the design's default.
  static const defaultStart = 18 * 60;
  static const defaultEnd = endOfDay;

  /// "12:00 AM" as an end time. The backend wants end > start on the same
  /// day (RN rule), so midnight is stored as 23:59.
  static const endOfDay = 23 * 60 + 59;

  factory HostDaySlot.fromJson(Map json) => HostDaySlot(
    enabled: json['enabled'] == true,
    start: J.integer(json['start']) ?? defaultStart,
    end: J.integer(json['end']) ?? defaultEnd,
  );

  final bool enabled;
  final int start;
  final int end;

  HostDaySlot copyWith({bool? enabled, int? start, int? end}) => HostDaySlot(
    enabled: enabled ?? this.enabled,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  JsonMap toJson() => {'enabled': enabled, 'start': start, 'end': end};

  /// Mon–Fri on, weekend off (the design's default week).
  static Map<HostWeekday, HostDaySlot> defaultWeek() => {
    for (final d in HostWeekday.values)
      d: HostDaySlot(
        enabled: d != HostWeekday.saturday && d != HostWeekday.sunday,
      ),
  };

  @override
  bool operator ==(Object other) =>
      other is HostDaySlot &&
      other.enabled == enabled &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(enabled, start, end);
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
