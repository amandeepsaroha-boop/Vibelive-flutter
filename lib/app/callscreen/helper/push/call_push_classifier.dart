import 'push_envelope.dart';

/// What a call push is telling this device (spec_call_native §4.3).
enum CallPushKind {
  /// A new ring with join credentials.
  invite,

  /// `CALL_ENDED` / declined / missed / cancelled (any side).
  ended,

  /// `CALL_ANSWERED_ELSEWHERE`: another of this user's devices took it.
  answeredElsewhere,

  /// Caller side: the receiver's phone rings (`CALL_RINGING`).
  remoteRinging,

  /// `CallTimer` / accepted / connected / status: never rings, never tears
  /// down (memory #5).
  ongoing,

  /// `MISSED_CALL_HISTORY`: the backend's own notification is the record.
  missedHistory,

  /// `PING_CLIENT`: an expert asks this client to call back.
  pingClient,

  /// Instant call: the system is ringing a new host (caller side).
  instantCallHostChanged,

  /// Instant call: a host accepted, call is connected (caller side).
  instantCallConnected,

  /// Instant call: no hosts available / timeout (caller side).
  instantCallFailed,

  /// Mentions a call but is not a call event (low balance, documents...).
  other,
}

/// Exact token lists (lower-case). Matched against `type`, the signal
/// (`action` / `event` / `eventType` / `notificationType`) and the status.
abstract final class CallPushTokens {
  static const invite = {
    'voicecall',
    'videocall',
    'voice_call',
    'video_call',
    'incoming_call',
    'new_call',
    'call_invite',
    'invite',
  };
  static const inviteSignals = {
    'voicecall',
    'videocall',
    'incoming_call',
    'call_incoming',
  };
  static const elsewhere = {
    'call_answered_elsewhere',
    'callansweredelsewhere',
    'answered_elsewhere',
  };
  static const missedHistory = {'missed_call', 'missed_call_history'};
  static const ended = {
    'call_ended',
    'callended',
    'call_end',
    'end_call',
    'callend',
    'end',
    'ended',
    'cancel',
    'cancelled',
    'canceled',
    'call_canceled',
    'call_cancelled',
    'decline',
    'declined',
    'rejected',
    'call_rejected',
    'call_busy',
    'timeout',
    'unanswered',
    'no_answer',
    'hangup',
    'hang_up',
  };

  /// RN `parseCallPush` status values that end a call.
  static const endedStatus = {
    'ended',
    'declined',
    'completed',
    'missed',
    'cancelled',
    'canceled',
  };

  /// Caller side only: never rings (E-75).
  static const remoteRinging = {
    'call_ringing',
    'callringing',
    'call_ringing_legacy',
    'ringing',
  };
  static const ongoing = {
    'calltimer',
    'call_timer',
    'ongoing_call',
    'ongoing_call_start',
    'ongoing_call_status',
    'ongoing',
    'call_ongoing',
    'call_update',
    'update',
    'updated',
    'connected',
    'connect',
    'answered',
    'accepted',
    'call_accepted',
    'in_call',
    'incall',
    'call_status',
    'status_update',
  };
  static const instantCall = {
    'instant_call_host_changed',
    'instant_call_connected',
    'instant_call_failed',
  };
  static const other = {
    'ping_client',
    'low_balance_warning',
    'call_doc_upload_enabled',
    'call_doc_uploaded',
  };

  /// `type` values that by themselves make a push call-like (the top-level
  /// gate). Only call-specific words: generic ones (`invite`, `update`,
  /// `end`, `accepted`...) also name referral / campaign / wallet pushes, so
  /// they count only once a call id, join credentials or the dismiss flag
  /// already admitted the push.
  static final Set<String> allTypes = {
    for (final t in {
      ...invite,
      ...elsewhere,
      ...missedHistory,
      ...ended,
      ...remoteRinging,
      ...ongoing,
      ...instantCall,
      ...other,
    })
      if (_callSpecific(t)) t,
    'call_ended_low_balance',
    ...instantCall,
  };

  /// Signals that by themselves make a push call-like.
  static final Set<String> allSignals = {
    for (final t in {
      ...inviteSignals,
      ...elsewhere,
      ...ended,
      ...remoteRinging,
      ...ongoing,
    })
      if (_callSpecific(t)) t,
  };

  static bool _callSpecific(String t) =>
      t.contains('call') || t.contains('elsewhere') || t == 'ping_client';
}

/// Call push kinds. Order: answered-elsewhere → missed-history → ended →
/// remote-ringing → ongoing → ping → invite → other. `category` is never
/// read: the backend fills it with a category id.
abstract final class CallPushClassifier {
  static CallPushKind classify(PushEnvelope m) {
    final d = m.data;
    final type = m.type;
    final signal = m.signal;
    final status = m.status;
    bool any(Set<String> s) =>
        s.contains(type) || s.contains(signal) || s.contains(status);

    // Elsewhere FIRST: it also carries dismissNotification:"true"; read as an
    // end it would tear down the device that answered (CE ordering).
    if (any(CallPushTokens.elsewhere)) return CallPushKind.answeredElsewhere;
    if (CallPushTokens.missedHistory.contains(type)) {
      return CallPushKind.missedHistory;
    }
    if (any(CallPushTokens.ended) ||
        CallPushTokens.endedStatus.contains(status) ||
        m.flag('dismissNotification')) {
      return CallPushKind.ended;
    }
    if (any(CallPushTokens.remoteRinging)) return CallPushKind.remoteRinging;
    if (m.flag('__isOngoingCall') ||
        m.flag('isOngoing') ||
        any(CallPushTokens.ongoing)) {
      return CallPushKind.ongoing;
    }
    if (type == 'instant_call_host_changed') {
      return CallPushKind.instantCallHostChanged;
    }
    if (type == 'instant_call_connected') {
      return CallPushKind.instantCallConnected;
    }
    if (type == 'instant_call_failed') {
      return CallPushKind.instantCallFailed;
    }
    if (type == 'ping_client') return CallPushKind.pingClient;
    if (isJoinable(d) &&
        (CallPushTokens.invite.contains(type) ||
            CallPushTokens.inviteSignals.contains(signal) ||
            type.isEmpty ||
            type == 'call')) {
      return CallPushKind.invite;
    }
    return CallPushKind.other;
  }

  /// A genuine ring is the only push carrying fresh Agora join credentials.
  static bool isJoinable(Map<String, String> d) =>
      (d['channelName'] ?? d['roomId'] ?? d['channel_name'] ?? '').isNotEmpty &&
      (d['token'] ?? d['receiverToken'] ?? '').isNotEmpty &&
      (d['callId'] ?? d['call_id'] ?? '').isNotEmpty;

  /// RN `isOngoingTap`: the "Ongoing Call" notification of a live call.
  static bool isOngoingTap(PushEnvelope m) =>
      m.flag('__isOngoingCall') ||
      m.type == 'calltimer' ||
      m.type == 'ongoing_call' ||
      (m.title ?? '').trim() == 'Ongoing Call';

  /// A missed-call record: the tap opens History.
  static bool isMissedTap(PushEnvelope m) =>
      CallPushTokens.missedHistory.contains(m.type) || m.status == 'missed';
}
