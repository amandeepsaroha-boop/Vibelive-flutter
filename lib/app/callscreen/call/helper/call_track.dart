import '../../../../core/analytics/events/call_ui_events.dart';
import '../../helper/call_controller.dart';
import '../../helper/call_runtime.dart';
import '../../helper/call_session.dart';

/// [CallInfo] (analytics) of [s].
CallInfo callInfoOf(CallSession s) {
  String? clean(String? v) =>
      v == null || v.isEmpty || v.toLowerCase() == 'null' ? null : v;
  return (
    callId: s.callId ?? s.callDocumentId,
    callType: s.isVideo ? 'video' : 'audio',
    role: s.isCaller ? 'caller' : 'receiver',
    hostId: s.isCaller
        ? clean(s.receiverDocId) ?? clean(s.remote.documentId)
        : null,
    phase: s.phase.name,
    instant: s.isInstantCall,
  );
}

/// The live call, else the one that just ended.
CallInfo currentCallInfo() {
  final now = CallController.instance.value;
  return callInfoOf(now.callId != null ? now : CallRuntime.lastCall);
}
