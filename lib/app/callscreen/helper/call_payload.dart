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
          avatarUrl: absoluteUrl(
            _pick(d, const ['ProfilePic', 'profilePic', 'callerImage']),
          ),
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

  /// Relative upload paths get the API host (E-72).
  static String? absoluteUrl(String? raw) {
    final s = raw?.trim();
    if (s == null || s.isEmpty) return null;
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return s;
    return '${Env.apiBaseUrl}${s.startsWith('/') ? s : '/$s'}';
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
