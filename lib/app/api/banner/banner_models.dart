import 'dart:convert';

import '../../../core/network/strapi.dart';

/// An unlocked milestone shown by the achievement modal: a
/// `/unlocked-milestones` row with its milestone's display fields merged in,
/// or a `milestone_unlocked` push payload.
///
/// Text from the backend wins; otherwise use the [preset] keys:
/// `m.title ?? context.t(m.preset.titleKey)`.
class UnlockedMilestone {
  const UnlockedMilestone(this.raw);

  factory UnlockedMilestone.fromRow(JsonMap row) {
    final milestone = Strapi.map(row['milestone']) ?? const {};
    Object? pick(String milestoneKey, String rowKey) =>
        _present(milestone[milestoneKey]) ?? _present(row[rowKey]);
    return UnlockedMilestone({
      ...row,
      'unlockedMilestoneDocumentId':
          _present(row['documentId']) ??
          _present(row['unlockedMilestoneDocumentId']),
      'milestoneDocumentId':
          _present(milestone['documentId']) ??
          _present(row['milestoneDocumentId']) ??
          _present(milestone['id']),
      'milestoneKey': pick('milestone_key', 'milestoneKey'),
      for (final field in _displayFields) field: pick(field, field),
    });
  }

  /// FCM data of a `milestone_unlocked` push (all values are strings).
  factory UnlockedMilestone.fromPush(Map<String, dynamic> data) =>
      UnlockedMilestone(Map<String, dynamic>.from(data));

  factory UnlockedMilestone.fromJson(Object? json) =>
      UnlockedMilestone(Map<String, dynamic>.from(json! as Map));

  final JsonMap raw;

  JsonMap toJson() => raw;

  static const _displayFields = [
    'title',
    'subtitle',
    'badgeLabel',
    'tierLabel',
    'iconName',
    'iconFamily',
    'primaryColor',
    'gradientColors',
  ];

  /// documentId of the unlocked row: what `MilestoneApi.markViewed` takes.
  String? get unlockedMilestoneDocumentId =>
      J.str(raw['unlockedMilestoneDocumentId']);

  /// Dedupe key for the modal queue.
  String? get id =>
      unlockedMilestoneDocumentId ??
      J.str(raw['documentId']) ??
      J.str(raw['id']);

  String? get milestoneDocumentId => J.str(raw['milestoneDocumentId']);
  String? get milestoneKey =>
      J.str(raw['milestoneKey']) ?? J.str(raw['milestone_key']);

  String? get title => _str(raw['title']);
  String? get subtitle => _str(raw['subtitle']);
  String? get tierLabel => _str(raw['tierLabel']);
  String? get badgeLabel => _str(raw['badgeLabel']);

  MilestonePreset get preset =>
      MilestonePreset.resolve([milestoneDocumentId, milestoneKey, raw['type']]);

  /// Two hex colours: the backend's `gradientColors` (list or JSON string),
  /// else the preset's.
  List<String> get gradient =>
      parseGradient(raw['gradientColors']) ?? preset.gradient;

  String get accent => _str(raw['primaryColor']) ?? preset.accent;

  String get iconFamily => _str(raw['iconFamily']) ?? 'MaterialCommunityIcons';

  /// Icon of [iconFamily].
  String get iconName => _str(raw['iconName']) ?? preset.iconName;

  /// First two entries of a colour list (or its JSON string), else null.
  static List<String>? parseGradient(Object? value) {
    var list = value;
    if (list is String) {
      try {
        list = jsonDecode(list);
      } on FormatException {
        return null;
      }
    }
    if (list is List && list.length >= 2) {
      return [for (final c in list.take(2)) '$c'];
    }
    return null;
  }

  static Object? _present(Object? v) => (v == null || v == '') ? null : v;

  static String? _str(Object? v) {
    final s = J.str(v)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}

/// Built-in look and copy per milestone (RN `milestones.config.js`), matched
/// case-insensitively on the backend milestone key / documentId.
class MilestonePreset {
  const MilestonePreset._({
    required this.key,
    required this.i18nId,
    required this.iconName,
    required this.gradient,
    required this.accent,
  });

  /// Backend key this preset matches ('' for [fallback]).
  final String key;
  final String i18nId;

  /// MaterialCommunityIcons name.
  final String iconName;
  final List<String> gradient;
  final String accent;

  String get categoryKey => 'banner:milestones.$i18nId.category';
  String get titleKey => 'banner:milestones.$i18nId.title';
  String get subtitleKey => 'banner:milestones.$i18nId.subtitle';
  String get badgeKey => 'banner:milestones.$i18nId.badge';

  static const _lime = '#A8EC4A';
  static const _rose = '#5E17EB';

  static const firstCall = MilestonePreset._(
    key: 'firstCall',
    i18nId: 'first_call',
    iconName: 'medal-outline',
    gradient: ['#A8EC4A', '#4ADE80'],
    accent: _lime,
  );

  static const minutes100 = MilestonePreset._(
    key: 'milestone100',
    i18nId: 'minutes_100',
    iconName: 'trophy-outline',
    gradient: ['#5E17EB', '#3A0CA3'],
    accent: _rose,
  );

  /// Backend spelling of the key is `moneyRecived`.
  static const moneyReceived = MilestonePreset._(
    key: 'moneyRecived',
    i18nId: 'money_received',
    iconName: 'cash',
    gradient: ['#3b82f6', '#1d4ed8'],
    accent: '#3b82f6',
  );

  static const hostVerified = MilestonePreset._(
    key: 'proLaunch',
    i18nId: 'pro_launch',
    iconName: 'shield-check-outline',
    gradient: ['#A8EC4A', '#5E17EB'],
    accent: _lime,
  );

  static const fallback = MilestonePreset._(
    key: '',
    i18nId: 'default',
    iconName: 'award-outline',
    gradient: [_lime, _rose],
    accent: _lime,
  );

  static const values = [firstCall, minutes100, moneyReceived, hostVerified];

  static MilestonePreset resolve(Iterable<Object?> candidates) {
    final wanted = {
      for (final c in candidates)
        if (J.str(c) case final s?) s.toLowerCase(),
    };
    for (final preset in values) {
      if (wanted.contains(preset.key.toLowerCase())) return preset;
    }
    return fallback;
  }
}
