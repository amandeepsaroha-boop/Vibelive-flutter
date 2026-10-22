import 'dart:convert';

import '../../../core/config/env.dart';
import 'call_session.dart';

/// A ring / accept payload from any door (FCM data, the VoIP relay, the
/// CallKit plugin `extra`, a notification, a stored snapshot), normalised
/// once (RN `normalizeCallPayload` + `receiveCall` + `handleNativeAccept`).
/// Every backend value arrives as a string.
class CallPayload {
  const CallPayload._({
    required this.session,
    required this.data,
    required this.ongoing,
    required this.autoOpen,
  });

  /// The receiver's view of the call (phase and role are set by
  /// `CallController.receive`).
  final CallSession session;

  /// The flattened raw payload.
  final Map<String, dynamic> data;

  /// `__isOngoingCall` / `isOngoing`: a rejoin, never re-sends UpdateCall.
  final bool ongoing;

  /// `__autoOpen`.
  final bool autoOpen;

  String get callId => session.callId!;

  /// Channel + token: only these can ring or be joined (E-7).
  bool get hasJoinCreds =>
      (session.channelName ?? '').isNotEmpty &&
      (session.token ?? '').isNotEmpty;

  /// Older than [ttl] by its `timestamp`. A payload without one is never
  /// stale (RN).
  bool isStale(Duration ttl, {DateTime? now}) {
    final sent = session.sentAt;
    return sent != null && (now ?? DateTime.now()).difference(sent) > ttl;
  }

  /// Same FCM message twice (E-2): `callId|event|status|messageId|sentTime|
  /// timestamp`.
  String get fingerprint => [
    callId,
    _pick(data, const ['event', 'type', 'action']),
    _pick(data, const ['status', 'callStatus']),
    _pick(data, const ['messageId', '__messageId', 'google.message_id']),
    _pick(data, const ['sentTime', 'google.sent_time']),
    _pick(data, const ['timestamp', 'ts']),
  ].map((v) => v ?? '').join('|');

  /// Null when there is no call id. [selfId]: the signed-in user's numeric
  /// id, the receiver when the payload leaves it out.
  static CallPayload? parse(Map<dynamic, dynamic> raw, {String? selfId}) {
    final d = flatten(raw);
    final callId = _pick(d, const ['callId', 'call_id', 'CallId']);
    if (callId == null) return null;
    final company = _anyTrue(d, const [
      'is_company_account',
      'isCompanyAccount',
      'is_company',
    ]);
    final type = (_pick(d, const ['type', 'callType']) ?? '').toLowerCase();
    final callerId = _pick(d, const ['callerId', 'caller_id']);
    final callerDocId = _pick(d, const ['calleridDocID', 'callerDocId']);
    final token = _pick(d, const ['token', 'receiverToken']);
    return CallPayload._(
      data: d,
      ongoing: _anyTrue(d, const ['__isOngoingCall', 'isOngoing']),
      autoOpen: _anyTrue(d, const ['__autoOpen']),
      session: CallSession(
        role: CallRole.receiver,
        callId: callId,
        callDocumentId: _pick(d, const ['callDocumentId']),
        channelName: _pick(d, const ['channelName', 'roomId', 'channel_name']),
        token: token == null ? null : repairToken(token),
        // The backend sends `hasVideo: "0"` for video calls: the type says
        // it (mem #13, E-37).
        isVideo:
            _anyTrue(d, const ['isVideo', 'hasVideo']) ||
            type.contains('video'),
        remote: CallPeer(
          id: callerId,
          documentId: callerDocId,
          name: displayName(
            _pick(d, const ['callerName', 'caller_name', 'name', 'handle']),
          ),
          avatarUrl: avatarOf(d),
          isCompany: company,
        ),
        callerId: callerId,
        receiverId: _pick(d, const ['receiverId', 'receiver_id']) ?? selfId,
        callerDocId: callerDocId,
        receiverDocId: _pick(d, const ['receiverDocID', 'receiverDocId']),
        category: _pick(d, const ['category']),
        categoryName: _pick(d, const ['categoryName', 'category_name']),
        callerIsCompany: company,
        sentAt: sentAt(_pick(d, const ['timestamp', 'ts'])),
        autoAccept: _anyTrue(d, const ['__autoAccept', 'autoAccept']),
        openedLocked: _anyTrue(d, const ['__unlock']),
      ),
    );
  }

  /// `data` nested (VoIP / plugin `extra`) wins over the top level, like
  /// the native `payload["data"] ?? payload`; other top-level keys stay.
  static Map<String, dynamic> flatten(Map<dynamic, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (k != 'data') out['$k'] = v;
    });
    final nested = raw['data'];
    if (nested is Map) nested.forEach((k, v) => out['$k'] = v);
    return out;
  }

  /// A `+` in base64 becomes a space after URL parsing; Agora then rejects
  /// the token (reason 8, E-52).
  static String repairToken(String token) => token.replaceAll(' ', '+').trim();

  /// `+` → space (URL-encoded names), trimmed; null when empty.
  static String? displayName(String? raw) {
    final s = raw?.replaceAll('+', ' ').trim();
    return s == null || s.isEmpty ? null : s;
  }

  /// Keys a ring payload carries the caller's photo under (the backend
  /// sends `ProfilePic`).
  static const avatarKeys = [
    'ProfilePic',
    'profilePic',
    'callerImage',
    'callerPic',
    'callerProfilePic',
    'avatar',
  ];

  /// The caller's photo in [d] (raw push / plugin `extra`) as an absolute
  /// URL, or null. Shared by the call screens ([parse]) and the Android
  /// system ringer, which can only load `http(s)` URLs (a relative path
  /// there becomes `file:///android_asset/...` and shows nothing).
  static String? avatarOf(Map<dynamic, dynamic> d) {
    for (final k in avatarKeys) {
      final url = absoluteUrl(d[k]);
      if (url != null) return url;
    }
    return null;
  }

  /// Relative upload paths get the API host (E-72). Also takes a
  /// protocol-relative URL and a Strapi media node (a map, or one sent as a
  /// JSON string). Null for anything without a usable URL.
  static String? absoluteUrl(Object? raw) {
    if (raw is Map) return absoluteUrl(_mediaUrl(raw));
    if (raw == null || raw is List) return null;
    final s = '$raw'.trim();
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'null' || lower == 'undefined') return null;
    if (s.startsWith('{')) {
      try {
        final decoded = jsonDecode(s);
        return decoded is Map ? absoluteUrl(_mediaUrl(decoded)) : null;
      } on FormatException {
        return null;
      }
    }
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return s;
    if (s.startsWith('//')) return 'https:$s';
    return '${Env.apiBaseUrl}${s.startsWith('/') ? s : '/$s'}';
  }

  /// `url` of a Strapi media node (v4 `data.attributes` or v5 flat),
  /// original first, then the largest format.
  static Object? _mediaUrl(Map<dynamic, dynamic> m) {
    final data = m['data'];
    if (data is Map) return _mediaUrl(data);
    final attrs = m['attributes'];
    if (attrs is Map) return _mediaUrl(attrs);
    final url = m['url'];
    if (url != null) return url;
    final formats = m['formats'];
    if (formats is! Map) return null;
    for (final f in const ['large', 'medium', 'small', 'thumbnail']) {
      final v = formats[f];
      if (v is Map && v['url'] != null) return v['url'];
    }
    return null;
  }

  /// Epoch seconds or milliseconds (`> 2e10` = ms, RN incoming route).
  static DateTime? sentAt(Object? raw) {
    final n = raw is num ? raw : num.tryParse('${raw ?? ''}'.trim());
    if (n == null || n <= 0) return null;
    final ms = n > 2e10 ? n.toInt() : (n * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// true / 'true' / 1 / '1'.
  static bool truthy(Object? v) => switch (v) {
    final bool b => b,
    final num n => n == 1,
    final String s => s.trim().toLowerCase() == 'true' || s.trim() == '1',
    _ => false,
  };

  static bool _anyTrue(Map<String, dynamic> d, List<String> keys) =>
      keys.any((k) => truthy(d[k]));

  /// First usable string; `null` / `Null` / `undefined` (the backend sends
  /// `receiverDocID: "Null"`) count as missing.
  static String? _pick(Map<String, dynamic> d, List<String> keys) {
    for (final k in keys) {
      final v = d[k];
      if (v == null || v is Map || v is List) continue;
      final s = '$v'.trim();
      if (s.isEmpty) continue;
      final lower = s.toLowerCase();
      if (lower == 'null' || lower == 'undefined') continue;
      return s;
    }
    return null;
  }

  /// [_pick] for other helpers (push type / status reads).
  static String? read(Map<String, dynamic> d, List<String> keys) =>
      _pick(d, keys);
}
