import '../../../../core/utils/log.dart';
import '../../../api/authscreen/push_api.dart';
import 'push_session.dart';

/// `EXPERT_PRESENCE_PROBE` answer (architecture decision 13, CE): the
/// backend pings experts whose sessions are Android-only; the device answers
/// `POST /api/expert-profiles/heartbeat`, which keeps it "online". RN never
/// answered (flagged to the backend). Experts only; never throws.
abstract final class HeartbeatHandler {
  static const _minGap = Duration(seconds: 20);
  static DateTime? _last;

  static Future<void> send({required String via}) async {
    if (!PushSession.isSignedIn || !PushSession.isExpert) return;
    final last = _last;
    final now = DateTime.now();
    // FCM + VoIP copies of one probe arrive together: answer once.
    if (last != null && now.difference(last) < _minGap) return;
    _last = now;
    try {
      await PushApi.expertHeartbeat(via: via);
    } catch (e) {
      Log.w('Heartbeat', 'failed: $e');
    }
  }
}
