import 'package:flutter/foundation.dart';

import '../../../core/network/strapi.dart';

enum InstantCallSessionStatus {
  searching,
  ringing,
  connected,
  completed,
  failed,
  cancelled,
  unknown;

  static InstantCallSessionStatus parse(Object? raw) {
    final s = (J.str(raw) ?? '').trim().toLowerCase();
    for (final v in values) {
      if (v != unknown && v.name == s) return v;
    }
    return unknown;
  }

  bool get isActive => this == searching || this == ringing;
  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;
}

class InstantCallHost {
  const InstantCallHost({
    this.userId,
    this.name,
    this.profilePic,
    this.ringAttemptIndex,
  });

  final String? userId;
  final String? name;
  final String? profilePic;
  final int? ringAttemptIndex;

  factory InstantCallHost.fromJson(Map<String, dynamic> json) =>
      InstantCallHost(
        userId: J.str(json['hostUserId']),
        name: J.str(json['hostName']),
        profilePic: J.str(json['hostProfilePic']),
        ringAttemptIndex: J.integer(json['ringAttemptIndex']),
      );

  factory InstantCallHost.fromPush(Map<String, dynamic> data) =>
      InstantCallHost(
        userId: J.str(data['hostUserId']),
        name: J.str(data['hostName']),
        profilePic: J.str(data['hostProfilePic']),
        ringAttemptIndex: J.integer(data['ringAttemptIndex']),
      );
}

class InitiatedInstantCall {
  const InitiatedInstantCall({
    required this.sessionId,
    required this.callerToken,
    required this.channelName,
    this.currentHost,
    this.parallelHosts,
    this.callerRate,
  });

  final String sessionId;
  final String callerToken;
  final String channelName;
  final InstantCallHost? currentHost;
  final List<InstantCallHost>? parallelHosts;

  /// ₹/min the caller pays for Talk Now (the config's caller rate).
  final double? callerRate;

  static InitiatedInstantCall? tryParse(Map<String, dynamic> body) {
    final sessionId = J.str(body['sessionId']);
    final token = J.str(body['callerToken']);
    final channel = J.str(body['channelName']);
    if (sessionId == null || token == null || channel == null) return null;

    final hostMap = body['currentHost'];
    final host = hostMap is Map<String, dynamic>
        ? InstantCallHost.fromJson(hostMap)
        : null;

    final parallelList = body['parallelHosts'];
    final parallel = parallelList is List
        ? [
            for (final h in parallelList)
              if (h is Map<String, dynamic>) InstantCallHost.fromJson(h),
          ]
        : null;

    return InitiatedInstantCall(
      sessionId: sessionId,
      callerToken: token,
      channelName: channel,
      currentHost: host ?? parallel?.firstOrNull,
      parallelHosts: parallel,
      callerRate: J.number(body['callerRate']),
    );
  }
}

/// `GET /instant-call/config`: Talk Now for the signed-in user.
@immutable
class InstantCallConfig {
  const InstantCallConfig({
    required this.enabled,
    this.allowedCallTypes = 'voice_only',
    this.callerVoiceRate,
    this.callerVideoRate,
    this.maxRingSeconds,
  });

  factory InstantCallConfig.fromJson(Map<String, dynamic> json) =>
      InstantCallConfig(
        enabled: J.boolean(json['enabled']),
        allowedCallTypes: J.str(json['allowedCallTypes']) ?? 'voice_only',
        callerVoiceRate: J.number(json['callerVoiceRate']),
        callerVideoRate: J.number(json['callerVideoRate']),
        maxRingSeconds: J.integer(json['maxRingSeconds']),
      );

  static const off = InstantCallConfig(enabled: false);

  final bool enabled;

  /// `voice_only`, `video_only` or `both`.
  final String allowedCallTypes;
  final double? callerVoiceRate;
  final double? callerVideoRate;

  /// How long the server searches for a host (null: an older backend).
  final int? maxRingSeconds;

  /// The call type the one-tap button places.
  bool get placesVideo => allowedCallTypes == 'video_only';
}

/// `POST /instant-call/host-accept`: the call record a Talk Now ring became.
@immutable
class InstantHostAccept {
  const InstantHostAccept({
    required this.callId,
    this.channelName,
    this.hostToken,
  });

  static InstantHostAccept? tryParse(Map<String, dynamic> body) {
    if (body['success'] == false) return null;
    final id = J.str(body['callId']);
    if (id == null) return null;
    final token = J.str(body['hostToken']);
    return InstantHostAccept(
      callId: id,
      channelName: J.str(body['channelName']),
      hostToken: token == null || token.isEmpty ? null : token,
    );
  }

  /// The `api::call.call` id: Callend bills it.
  final String callId;
  final String? channelName;
  final String? hostToken;
}
