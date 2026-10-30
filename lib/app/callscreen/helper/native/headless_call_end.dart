import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_api.dart';
import '../../../api/callscreen/call_errors.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/pending_decline_queue.dart';
import '../../../api/instant_call/instant_call_api.dart';
import '../call_payload.dart';
import '../push/push_session.dart';
import 'native_call_marks.dart';

/// Android `/call/Callend` for a system-UI action the call logic cannot see
/// (no UI isolate, or a call the UI isolate never adopted): the notification
/// Decline of a killed app, the ongoing notification's Hang up. RN headless
/// task + `pendingDeclineQueue`. The ended mark is written BEFORE the
/// request, so an echo of the same event is recognised. Never throws.
abstract final class HeadlessCallEnd {
  static const _tag = 'HeadlessCallEnd';

  /// A ringing call declined from the notification.
  static Future<void> decline(String callId, Map<String, dynamic> extra) async {
    if (!await _claim(callId)) return;
    // Talk Now: the server rings the next host now.
    if (_instant(extra)) {
      await InstantCallApi.hostDecline(_session(callId, extra));
      return;
    }
    final by = _str(extra['receiverId']) ?? PushSession.userId;
    if (by == null) {
      Log.w(_tag, 'decline $callId: no endedById');
      return;
    }
    await _send(
      CallEndInput.decline(
        callId: callId,
        endedById: by,
        type: CallType.parse(extra['type']),
        callerDocumentId: _str(extra['calleridDocID']),
      ),
    );
  }

  /// The ongoing notification's Hang up: `completed` with the measured
  /// duration when the call connected, else a receiver decline.
  static Future<void> hangUp(String callId, Map<String, dynamic> extra) async {
    if (!await _claim(callId)) return;
    final caller = extra['__role'] == 'caller';
    final me =
        _str(caller ? extra['callerId'] : extra['receiverId']) ??
        PushSession.userId;
    if (me == null) {
      Log.w(_tag, 'hang up $callId: no endedById');
      return;
    }
    final type = CallType.parse(extra['type']);
    final doc = _str(extra['calleridDocID']);
    final connectedAt = await NativeCallMarks.connectedAt(callId);
    await NativeCallMarks.clearConnected(callId);
    final instant = _instant(extra);
    if (instant && connectedAt == null) {
      // A search (caller) or a ring (host): no call record to end.
      final session = _session(callId, extra);
      caller
          ? await _quiet(() => InstantCallApi.cancel(session))
          : await InstantCallApi.hostDecline(session);
      return;
    }
    // Talk Now bills the call record the accept created, not the ring id.
    final billId = instant ? await _recordOf(callId, extra, caller) : callId;
    if (billId == null) {
      Log.w(_tag, 'hang up $callId: Talk Now call record unknown');
      return;
    }
    if (connectedAt == null) {
      await _send(
        caller
            ? CallEndInput.cancel(
                callId: callId,
                endedById: me,
                type: type,
                callerDocumentId: doc,
              )
            : CallEndInput.decline(
                callId: callId,
                endedById: me,
                type: type,
                callerDocumentId: doc,
              ),
      );
      return;
    }
    final now = DateTime.now();
    final secs = now.difference(connectedAt).inSeconds;
    await _send(
      CallEndInput(
        callId: billId,
        endedById: me,
        status: CallStatus.completed,
        startTime: connectedAt,
        endTime: now,
        durationSeconds: secs < 1 ? 1 : secs,
        type: type,
        callerDocumentId: doc,
      ),
    );
  }

  /// False when the app ended this call itself or it is already over.
  static Future<bool> _claim(String callId) async {
    if (callId.isEmpty) return false;
    if (await NativeCallMarks.isAppEnded(callId)) return false;
    if (await NativeCallMarks.isEnded(callId)) return false;
    await NativeCallMarks.markEnded(callId);
    return true;
  }

  static Future<void> _send(CallEndInput input) async {
    try {
      await CallApi.endCall(input);
    } on ApiException catch (e) {
      if (e.isBenignDecline || e.isCallAlreadyEnded) return;
      await PendingDeclineQueue.enqueue(input);
    } catch (_) {
      await PendingDeclineQueue.enqueue(input);
    }
  }

  static bool _instant(Map<String, dynamic> extra) =>
      CallPayload.truthy(extra['isInstantCall']);

  static String _session(String callId, Map<String, dynamic> extra) =>
      _str(extra['instantCallSessionId']) ?? callId;

  /// The Talk Now call record: saved at the accept, else asked for (the
  /// host's accept repeats its answer; the caller reads the status).
  static Future<String?> _recordOf(
    String callId,
    Map<String, dynamic> extra,
    bool caller,
  ) async {
    final saved = await NativeCallMarks.serverCallId(callId);
    if (saved != null) return saved;
    final session = _session(callId, extra);
    try {
      return caller
          ? await InstantCallApi.connectedCallId(session)
          : (await InstantCallApi.hostAccept(session)).callId;
    } catch (e) {
      Log.w(_tag, 'Talk Now record of $callId: $e');
      return null;
    }
  }

  static Future<void> _quiet(Future<void> Function() job) async {
    try {
      await job();
    } catch (_) {}
  }

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty || s == 'null' ? null : s;
  }
}
