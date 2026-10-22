import 'dart:io' show Platform;

import 'package:flutter_callkit_incoming/entities/entities.dart';

import '../push/push_strings.dart';

/// CallKit / plugin ids for a call.
abstract final class CallKitIds {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// The CallKit UUID native code reports a call under. MUST be byte-identical
  /// to `VibeCallKit.nativeId(for:)` in Swift: FNV-1a over UTF-16 code units,
  /// wrapping 64-bit, the second hash salted with `vibelive:`, then the
  /// v4 / RFC-4122 bits. A UUID passes through, lower-cased.
  static String nativeIdFor(String callId) {
    if (_uuid.hasMatch(callId)) return callId.toLowerCase();
    final a = _fnv1a(callId, 0xcbf29ce484222325);
    final b = _fnv1a('vibelive:$callId', 0x84222325cbf29ce4);
    final bytes = List<int>.generate(16, (i) {
      final hash = i < 8 ? a : b;
      return (hash >> (8 * (7 - (i % 8)))) & 0xff;
    });
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// The id the plugin knows a call by on this platform: the CallKit UUID on
  /// iOS, the call id itself on Android.
  static String platformIdFor(String callId) =>
      Platform.isIOS ? nativeIdFor(callId) : callId;

  /// 64-bit wrapping FNV-1a (Dart ints wrap on multiply; `>>` is arithmetic,
  /// but every byte is masked, so the sign never leaks).
  static int _fnv1a(String input, int seed) {
    var hash = seed;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return hash;
  }
}

/// `flutter_callkit_incoming` params (spec_call_native §3.1). Android only:
/// on iOS native code builds every CallKit report itself.
abstract final class CallKitParamsBuilder {
  static const appName = 'Vibe Live';

  /// Ring window bounds (RN Android TTL 45 s).
  static const minRing = Duration(seconds: 5);
  static const maxRing = Duration(seconds: 45);

  /// Incoming ringer for [data] (raw push values). [ring]: what is left of
  /// the invite's life. Call [PushStrings.ensure] first.
  static CallKitParams incoming(
    Map<String, dynamic> data, {
    required String callId,
    required Duration ring,
  }) {
    final video = isVideo(data);
    final category = _category(data);
    final base = PushStrings.t(video ? 'call.incoming_video' : 'call.incoming');
    return CallKitParams(
      id: callId,
      nameCaller: callerName(data),
      appName: appName,
      avatar: _str(data['ProfilePic']) ?? _str(data['profilePic']),
      handle: category == null ? base : '$base • $category',
      type: video ? 1 : 0,
      duration: ring.inMilliseconds.clamp(
        minRing.inMilliseconds,
        maxRing.inMilliseconds,
      ),
      extra: {...data, 'callId': callId},
      // The backend sends its own "Missed Call" notification.
      missedCallNotification: const NotificationParams(showNotification: false),
      callingNotification: _calling(video),
      android: _android,
    );
  }

  /// The ongoing-call notification (foreground service) for [callId]. Same
  /// id as the ringer, so it replaces it.
  static CallKitParams ongoing(
    String callId, {
    required String name,
    required bool video,
    Map<String, dynamic> extra = const {},
  }) => CallKitParams(
    id: callId,
    nameCaller: name,
    appName: appName,
    handle: PushStrings.t(video ? 'call.ongoing_video' : 'call.ongoing_voice'),
    type: video ? 1 : 0,
    duration: 60 * 60 * 1000,
    extra: {...extra, 'callId': callId},
    missedCallNotification: const NotificationParams(showNotification: false),
    callingNotification: _calling(video),
    android: _android,
  );

  /// Id-only params (hide / end).
  static CallKitParams bare(String callId) => CallKitParams(
    id: callId,
    appName: appName,
    extra: {'callId': callId},
    android: _android,
  );

  static NotificationParams _calling(bool video) => NotificationParams(
    showNotification: true,
    subtitle: PushStrings.t(
      video ? 'call.ongoing_video' : 'call.ongoing_voice',
    ),
    isShowCallback: true,
    callbackText: PushStrings.t('call.end_call'),
  );

  static AndroidParams get _android => AndroidParams(
    // CallStyle (RN parity): Android 14 cannot swipe away a CallStyle FGS
    // notification.
    isCustomNotification: false,
    isShowFullLockedScreen: true,
    // A direct activity launch is blocked for background apps (CE): the
    // notification's full-screen intent is what the OS honours.
    isFullScreen: false,
    ringtonePath: 'reciver_side_ringing',
    isImportant: true,
    backgroundColor: '#080808',
    actionColor: '#561DE2',
    textColor: '#FFFFFF',
    incomingCallNotificationChannelName: 'Incoming calls',
    missedCallNotificationChannelName: 'Missed calls',
    textAccept: PushStrings.t('call.accept'),
    textDecline: PushStrings.t('call.decline'),
  );

  /// `hasVideo` / `isVideo`, or a type containing "video" (the backend sends
  /// `hasVideo: "0"` for video calls, memory #13).
  static bool isVideo(Map<String, dynamic> d) =>
      _truthy(d['hasVideo']) ||
      _truthy(d['isVideo']) ||
      (_str(d['type']) ?? '').toLowerCase().contains('video');

  /// VoIP payloads encode spaces as "+".
  static String callerName(Map<String, dynamic> d) =>
      (_str(d['callerName']) ??
              _str(d['caller_name']) ??
              _str(d['handle']) ??
              _str(d['name']) ??
              appName)
          .replaceAll('+', ' ');

  /// `categoryName` only: `category` is an id.
  static String? _category(Map<String, dynamic> d) {
    final name = _str(d['categoryName']) ?? _str(d['category_name']);
    if (name == null || int.tryParse(name) != null) return null;
    return name;
  }

  static bool _truthy(Object? v) {
    if (v is bool) return v;
    final s = '${v ?? ''}'.toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  static String? _str(Object? v) {
    final s = v?.toString().trim();
    return s == null || s.isEmpty || s == 'null' ? null : s;
  }
}
