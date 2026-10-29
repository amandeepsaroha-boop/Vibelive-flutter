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
  });

  final String sessionId;
  final String callerToken;
  final String channelName;
  final InstantCallHost? currentHost;
  final List<InstantCallHost>? parallelHosts;

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
    );
  }
}
