/// What the Agora engine tells the call logic (internal stream; the screens
/// read `CallEngine.media` instead). A broadcast stream, so nothing depends
/// on a screen being mounted when the event fires (E-42).
sealed class CallEngineEvent {
  const CallEngineEvent();
}

/// This device is in [channel] as [uid].
class EngineJoined extends CallEngineEvent {
  const EngineJoined(this.channel, this.uid);
  final String channel;
  final int uid;
}

/// The other side arrived (first time, or back after a drop).
class EngineRemoteJoined extends CallEngineEvent {
  const EngineRemoteJoined(this.uid);
  final int uid;
}

/// The other side left. [quit]: hung up on purpose (Agora offline reason
/// 0) → end now; otherwise dropped → grace period.
class EngineRemoteLeft extends CallEngineEvent {
  const EngineRemoteLeft(this.uid, {required this.quit});
  final int uid;
  final bool quit;
}

/// Our connection is reconnecting (true) or back (false).
class EngineReconnecting extends CallEngineEvent {
  const EngineReconnecting(this.reconnecting);
  final bool reconnecting;
}

/// The call's token is about to expire (or expired). There is no renew
/// endpoint: the call ends (E-88).
class EngineTokenExpiring extends CallEngineEvent {
  const EngineTokenExpiring();
}

/// The join failed for good (no engine, rejected token, connection failed
/// before join). RN: local teardown, no retry (E-56).
class EngineJoinFailed extends CallEngineEvent {
  const EngineJoinFailed(this.reason);
  final String reason;
}

/// Our connection failed for good AFTER the join (Agora
/// `CONNECTION_STATE_FAILED`: the same uid joined elsewhere, banned by the
/// server, token revoked). The call cannot go on here (A7).
class EngineConnectionLost extends CallEngineEvent {
  const EngineConnectionLost(this.reason);
  final String reason;
}
