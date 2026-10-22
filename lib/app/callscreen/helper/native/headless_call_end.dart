import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/log.dart';
import '../../../api/callscreen/call_api.dart';
import '../../../api/callscreen/call_errors.dart';
import '../../../api/callscreen/call_models.dart';
import '../../../api/callscreen/pending_decline_queue.dart';
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
        callId: callId,
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

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty || s == 'null' ? null : s;
  }
}
