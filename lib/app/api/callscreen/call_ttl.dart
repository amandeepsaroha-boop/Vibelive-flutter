import '../../../core/network/strapi.dart';

/// Age limits for incoming-call payloads (RN `callTtl.ts` and the stale
/// checks in CallManager / IncomingCallScreen).
abstract final class CallTtl {
  /// VoIP invite TTL: 45 s leaves room for network delays.
  static const invite = Duration(seconds: 45);

  /// Payload replayed from a notification / cold start: older than this is a
  /// ghost call — don't present it and don't send a decline for it.
  static const incomingPayload = Duration(minutes: 2);

  /// Killed-state launch (root layout): an older call payload is not routed.
  static const coldStartRoute = Duration(minutes: 5);

  /// [timestamp] is epoch milliseconds (int, or a numeric string as sent in
  /// push payloads). A missing or unparsable timestamp is never stale.
  static bool isStale(
    Object? timestamp, {
    Duration ttl = invite,
    DateTime? now,
  }) {
    final ts = J.integer(timestamp);
    if (ts == null || ts <= 0) return false;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return nowMs - ts > ttl.inMilliseconds;
  }
}
