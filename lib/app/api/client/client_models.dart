import 'dart:math' as math;

import '../../../core/network/strapi.dart';

/// A Strapi entity (or the first one of a to-many relation), or null when the
/// relation is empty — including the v4 `{data: null}` shape.
JsonMap? strapiEntity(dynamic value) {
  final node = Strapi.node(value);
  final first = node is List ? (node.isEmpty ? null : node.first) : node;
  final map = Strapi.map(first);
  if (map == null || map.isEmpty) return null;
  if (map.containsKey('data') && map['data'] == null) return null;
  return map;
}

String? _text(dynamic v) {
  final s = J.str(v)?.trim();
  return (s == null || s.isEmpty) ? null : s;
}

// ── Profile ──────────────────────────────────────────────────────────────

/// A public user with their expert (host) profile: RN `fetchUserWithExpert`.
/// [user] is the raw public-user, [expert] the normalized expert (or null for
/// a client account). Persisted as "my profile" and mirrored into the session.
class UserWithExpert {
  const UserWithExpert({required this.user, this.expert});

  factory UserWithExpert.fromUser(JsonMap user) =>
      UserWithExpert(user: user, expert: normalizeExpert(user['expert']));

  factory UserWithExpert.fromJson(Object? json) {
    final map = json! as Map;
    final expert = map['expert'];
    return UserWithExpert(
      user: Map<String, dynamic>.from(map['user'] as Map),
      expert: expert is Map ? Map<String, dynamic>.from(expert) : null,
    );
  }

  final JsonMap user;
  final JsonMap? expert;

  Map<String, dynamic> toJson() => {'user': user, 'expert': expert};

  int? get id => J.integer(user['id']);
  String? get documentId => J.str(user['documentId']);
  String? get name => _text(user['name']);
  String? get email => _text(user['email']);
  String? get mobile => _text(user['mobile']);
  String? get profilePicUrl => Strapi.mediaFromAsset(user['profilePic']);

  /// Media id of the current photo (kept on profile saves).
  Object? get profilePicId => strapiEntity(user['profilePic'])?['id'];

  GeoOption? get state => GeoOption.fromRelation(user['state']);
  GeoOption? get district => GeoOption.fromRelation(user['district']);
  GeoOption? get city => GeoOption.fromRelation(user['city']);
  GeoOption? get country => GeoOption.fromRelation(user['country']);

  JsonMap get addressJson {
    final a = user['address_JSON'];
    return a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{};
  }

  bool get isExpert =>
      expert != null &&
      (expert!['id'] != null || expert!['documentId'] != null);

  /// documentId (or id) of the expert profile.
  String? get expertId => J.str(expert?['documentId']) ?? J.str(expert?['id']);

  bool get isCompanyAccount =>
      J.boolean(user['is_company_account']) ||
      J.boolean(user['isCompanyAccount']) ||
      J.boolean(user['is_company']);

  /// Name, email and mobile are all set ("finished registration").
  bool get isPersonalInfoComplete =>
      name != null && email != null && mobile != null;

  /// The profile handler, whatever shape the record came in (RN
  /// `getExpertHandler`).
  String? get handler {
    final nested = strapiEntity(user['expert_profile']);
    final rawExpert = strapiEntity(user['expert']);
    return _text(expert?['handler']) ??
        _text(rawExpert?['handler']) ??
        _text(user['handler']) ??
        _text(nested?['handler']) ??
        _text(user['username']) ??
        _text(user['slug']);
  }

  /// Slug of the public profile link: the handler (what the website resolves),
  /// else an id so a profile without a handler still gets a working link.
  String? get shareSlug =>
      handler ?? expertId ?? documentId ?? (id == null ? null : '$id');

  /// RN `normalizeExpert`: unwraps every relation the profile screens read.
  static JsonMap? normalizeExpert(dynamic expert) {
    final node = strapiEntity(expert);
    if (node == null) return null;
    return {
      ...node,
      'audio_intro': strapiEntity(node['audio_intro']),
      'language': Strapi.list(node['language']),
      'schedule': [
        for (final row in Strapi.list(node['schedule'])) _scheduleRow(row),
      ],
      'rates': Strapi.map(node['rates']) ?? <String, dynamic>{},
      'durations': Strapi.map(node['durations']) ?? <String, dynamic>{},
      'expert_profile_approvals': Strapi.list(node['expert_profile_approvals']),
      'expert_verifications': Strapi.list(node['expert_verifications']),
      'host_profile_images': Strapi.list(node['host_profile_images']),
    };
  }

  static JsonMap _scheduleRow(JsonMap row) => {
    ...row,
    'days': (J.str(row['days']) ?? '').trim(),
    'timeSlots': [
      for (final slot in Strapi.list(row['timeSlots']))
        if (J.str(slot['startTime']) != null && J.str(slot['endTime']) != null)
          slot,
    ],
  };
}

// ── Geo ──────────────────────────────────────────────────────────────────

/// Which state key a district lookup filters on.
enum GeoIdField { documentId, id }

/// Country / state / district row (also a populated relation on a user or a
/// GST record).
class GeoOption {
  const GeoOption(this.raw);

  /// A populated relation, a to-many list, or a bare id / documentId.
  static GeoOption? fromRelation(dynamic relation) {
    final node = Strapi.node(relation);
    if (node is num) return GeoOption({'id': node});
    if (node is String) {
      final s = node.trim();
      if (s.isEmpty) return null;
      final asInt = int.tryParse(s);
      return GeoOption(asInt != null ? {'id': asInt} : {'documentId': s});
    }
    final map = strapiEntity(node);
    if (map == null) return null;
    final option = GeoOption(map);
    final empty =
        option.id == null && option.documentId == null && option.name.isEmpty;
    return empty ? null : option;
  }

  final JsonMap raw;

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// Display name; some datasets use `stateNames` / `districtNames` /
  /// `cityNames` instead of `name`.
  String get name =>
      _text(raw['name']) ??
      _text(raw['stateNames']) ??
      _text(raw['districtNames']) ??
      _text(raw['cityNames']) ??
      '';

  /// Value + field to filter child rows by (documentId first).
  String? get filterId => documentId ?? (id == null ? null : '$id');
  GeoIdField get filterField =>
      documentId != null ? GeoIdField.documentId : GeoIdField.id;

  /// Plain relation value for component fields (GST): id first.
  Object? get relationId => id ?? documentId;

  /// Strapi `connect` payload for a relation field, or null.
  JsonMap? get connect {
    final numId = id;
    if (numId != null && numId != 0) {
      return {
        'connect': [
          {'id': numId},
        ],
      };
    }
    final doc = documentId ?? _text(raw['slug']);
    if (doc == null) return null;
    return {
      'connect': [
        {'documentId': doc},
      ],
    };
  }

  JsonMap toJson() => raw;
}

// ── Blocks ───────────────────────────────────────────────────────────────

/// Row of `GET /user-blocks` (custom controller, not Strapi-wrapped).
class BlockedUser {
  const BlockedUser(this.raw);

  final JsonMap raw;

  JsonMap get user => strapiEntity(raw['user']) ?? const {};
  JsonMap get expert => strapiEntity(user['expert']) ?? const {};

  /// What `unblock` expects (user documentId first).
  String? get targetUserId =>
      J.str(user['documentId']) ??
      J.str(user['id']) ??
      J.str(raw['targetUserId']) ??
      J.str(raw['blockDocumentId']);

  /// Null ⇒ show `client:fallback.blocked_user`.
  String? get name => _text(user['name']);
  String? get handle => _text(expert['handler']);
  String? get tagline => _text(expert['tagline']);
  String? get role => user['role'] is String ? _text(user['role']) : null;

  String? get profilePicUrl {
    final pic = user['profilePic'];
    return pic is String ? Strapi.mediaUrl(pic) : Strapi.mediaFromAsset(pic);
  }

  DateTime? get blockedAt => J.date(raw['blockedAt']);
}

// ── Favourites ───────────────────────────────────────────────────────────

/// One favourite host (`/favorites` row with its first expert).
class FavoriteExpert {
  const FavoriteExpert({
    required this.raw,
    this.id,
    this.documentId,
    this.expertId,
    this.expertName,
    this.expertHandle = '',
    this.expertVerified = false,
    this.profilePicUrl,
  });

  factory FavoriteExpert.fromRow(JsonMap row) {
    final experts = Strapi.list(row['experts']);
    final expert = experts.isEmpty ? const <String, dynamic>{} : experts.first;
    final user = strapiEntity(expert['user']) ?? const <String, dynamic>{};
    final verified = expert['isVerified'];
    return FavoriteExpert(
      raw: row,
      id: J.str(row['documentId']) ?? J.str(row['id']),
      documentId: J.str(row['documentId']),
      expertId: J.str(expert['documentId']) ?? J.str(expert['id']),
      expertName: _text(user['name']) ?? _text(expert['handler']),
      expertHandle: _text(expert['handler']) ?? '',
      expertVerified:
          verified == true || '${verified ?? ''}'.toLowerCase() == 'true',
      profilePicUrl: Strapi.mediaFromAsset(user['profilePic']),
    );
  }

  final JsonMap raw;

  /// documentId, else numeric id, of the favourite row.
  final String? id;
  final String? documentId;
  final String? expertId;

  /// Null ⇒ show `client:fallback.expert_name`.
  final String? expertName;
  final String expertHandle;
  final bool expertVerified;
  final String? profilePicUrl;

  /// One row per host, first (newest) wins.
  static List<FavoriteExpert> dedupe(Iterable<FavoriteExpert> rows) {
    final seen = <String>{};
    return [
      for (final row in rows)
        if ((row.expertId ?? row.id ?? '') case final key
            when key.isNotEmpty && seen.add(key))
          row,
    ];
  }
}

// ── GST ──────────────────────────────────────────────────────────────────

/// The user's `gst_detail` (RN `fetchGstDetails`). [raw] is null when the
/// user never submitted one.
class GstDetails {
  const GstDetails(this.raw);

  factory GstDetails.fromUser(JsonMap? user) =>
      GstDetails(strapiEntity(user?['gst_detail']));

  final JsonMap? raw;

  JsonMap get _gst => strapiEntity(raw?['GST']) ?? const {};
  JsonMap get _device => strapiEntity(raw?['gst_device_info']) ?? const {};

  bool get isSubmitted => raw != null;

  /// Pass back as `gstDetailId` so a save updates this row instead of
  /// creating a duplicate.
  String? get documentId => J.str(raw?['documentId']) ?? J.str(raw?['id']);

  bool get isVerified => J.boolean(raw?['Is_Verified']);

  bool get isGstRegistered {
    final v = _device['is_gst_registered'];
    return v == true || '${v ?? ''}'.toLowerCase() == 'true';
  }

  String get declarationStatement =>
      _text(_device['declaration_statement']) ?? '';

  String get gstNumber => _text(_gst['GST_Number']) ?? '';
  String get businessName => _text(_gst['Business_Name']) ?? '';
  String get address =>
      _text(_gst['addressLine']) ?? _text(_gst['Address']) ?? '';
  String get zipcode => _text(_gst['zipcode']) ?? '';

  GeoOption? get state =>
      GeoOption.fromRelation(_gst['State'] ?? _gst['state']);

  GeoOption? get district => GeoOption.fromRelation(
    _gst['District'] ?? _gst['district'] ?? _gst['City'] ?? _gst['city'],
  );

  GeoOption? get city =>
      GeoOption.fromRelation(_gst['City'] ?? _gst['city']) ?? district;

  JsonMap? get gstFile => strapiEntity(_gst['GST_File']);
  JsonMap? get logo => strapiEntity(_gst['Logo']);
  String? get gstFileUrl =>
      gstFile == null ? null : Strapi.mediaFromAsset(gstFile);
  String? get logoUrl => logo == null ? null : Strapi.mediaFromAsset(logo);
}

// ── Referral ─────────────────────────────────────────────────────────────

/// Referral screen data (RN `fetchReferralDashboard`). Share links are built
/// from [referralCode] by the deep-link layer (`?r=r` referral, `?r=i` invite).
class ReferralDashboard {
  const ReferralDashboard({
    required this.referralCode,
    this.totalClicks = 0,
    this.joinedUserCount = 0,
    this.joinedUsers = const [],
    this.referral,
  });

  factory ReferralDashboard.fromUser(
    JsonMap? user,
    List<JoinedUser> joinedUsers,
  ) {
    final referral = referralOf(user);
    return ReferralDashboard(
      referralCode: codeFrom(user),
      totalClicks:
          J.integer(referral?['totalClicks'] ?? referral?['copyCount']) ?? 0,
      joinedUserCount: math.max(
        J.integer(referral?['joinedUserCount']) ?? 0,
        joinedUsers.length,
      ),
      joinedUsers: joinedUsers,
      referral: referral,
    );
  }

  /// `user_referral` row (first one when the relation is a list).
  static JsonMap? referralOf(JsonMap? user) =>
      strapiEntity(user?['user_referral']);

  /// Upper-cased code, '' when the user has none. Falls back to
  /// `referrerCode` like RN.
  static String codeFrom(JsonMap? user) {
    final referral = referralOf(user);
    final code =
        _text(referral?['referralCode']) ??
        _text(referral?['code']) ??
        _text(user?['referrerCode']) ??
        '';
    return code.toUpperCase();
  }

  final String referralCode;
  final int totalClicks;
  final int joinedUserCount;
  final List<JoinedUser> joinedUsers;
  final JsonMap? referral;

  bool get hasCode => referralCode.isNotEmpty;

  /// Same dashboard with the share counter at [clicks] (after a share).
  ReferralDashboard withClicks(int clicks) => ReferralDashboard(
    referralCode: referralCode,
    totalClicks: clicks,
    joinedUserCount: joinedUserCount,
    joinedUsers: joinedUsers,
    referral: referral,
  );
}

/// Someone who signed up with the user's code.
class JoinedUser {
  const JoinedUser({
    this.id,
    this.name,
    this.mobile = '',
    this.profilePicUrl,
    this.joinedAt,
  });

  factory JoinedUser.fromRow(JsonMap row) {
    final mobile = _text(row['mobile']) ?? '';
    final name = _text(row['name']) ?? _text(row['username']);
    return JoinedUser(
      id: J.str(row['documentId']) ?? J.str(row['id']),
      name: name ?? (mobile.isEmpty ? null : maskMobile(mobile)),
      mobile: mobile,
      profilePicUrl: Strapi.mediaFromAsset(row['profilePic']),
      joinedAt: J.date(row['createdAt']),
    );
  }

  final String? id;

  /// Name, else the masked mobile. Null ⇒ show `client:fallback.user_name`.
  final String? name;
  final String mobile;
  final String? profilePicUrl;
  final DateTime? joinedAt;

  /// `98******10`: first and last two digits, at least six stars.
  static String maskMobile(String mobile) {
    if (mobile.length < 4) return mobile;
    final stars = '*' * math.max(mobile.length - 4, 6);
    return '${mobile.substring(0, 2)}$stars'
        '${mobile.substring(mobile.length - 2)}';
  }
}
