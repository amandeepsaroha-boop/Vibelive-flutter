import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../../core/utils/log.dart';
import '../push/push_strings.dart';
import 'callkit_params.dart';

/// What the system call UI just did.
enum CallKitAction {
  incoming,
  started,
  accepted,
  declined,
  ended,
  timedOut,
  connected,

  /// Android missed-call "Call back", or the ongoing notification's Hang up
  /// on some OEMs.
  callback,

  /// iOS: CallKit (de)activated the audio session ([CallKitSignal.flag]).
  audioSession,
  voipTokenUpdated,
}

/// One plugin event, flattened.
class CallKitSignal {
  const CallKitSignal({
    required this.action,
    this.callId = '',
    this.nativeId = '',
    this.extra = const {},
    this.flag = false,
  });

  final CallKitAction action;

  /// The app's call id ('' when unknown: e.g. a compliance UUID's timeout).
  final String callId;

  /// The id the plugin knows the call by (CallKit UUID on iOS).
  final String nativeId;

  /// The `extra` the call was shown with: the whole push payload.
  final Map<String, dynamic> extra;
  final bool flag;

  /// iOS PushKit compliance throwaway (§2.9): never a real call.
  bool get isCompliance {
    final v = extra['__compliance'];
    return v == true || v == 'true' || v == 1 || v == '1';
  }
}

/// A call the plugin considers active.
class NativeCall {
  const NativeCall({
    required this.nativeId,
    required this.callId,
    required this.isAccepted,
    required this.extra,
  });

  final String nativeId;
  final String callId;
  final bool isAccepted;
  final Map<String, dynamic> extra;

  bool get isCompliance {
    final v = extra['__compliance'];
    return v == true || v == 'true' || v == 1 || v == '1';
  }
}

/// `flutter_callkit_incoming` 3.1.6 wrapper (CE port). On iOS, Dart NEVER
/// shows, starts, ends or hides a CallKit call: native owns every report
/// (decision 15, §2.9). Allowed there: [listen], [activeCalls], [voipToken]
/// and [endAll] (sign-out); an in-app accept of a CallKit-ringing call goes
/// through `NativeCallBridge.answerLive`. Every method never throws.
abstract final class CallKitService {
  static const _tag = 'CallKitService';

  static final _signals = StreamController<CallKitSignal>.broadcast();
  static StreamSubscription<CallEvent?>? _sub;

  /// nativeId → callId, filled by every event / active-call read, so an
  /// id-only event (timeout, connected, callback) finds its call.
  static final _callIdByNativeId = <String, String>{};

  /// Android: rings whose sound and notification [hideIncoming] took down
  /// (the in-app screen took over). The plugin still lists them as active.
  static final _hidden = <String>{};

  /// Android: [callId]'s ringer was hidden by the app (it is not audible).
  static bool wasHidden(String callId) => _hidden.contains(callId);

  static Stream<CallKitSignal> get signals => _signals.stream;

  /// Starts listening (idempotent). UI isolate only: on Android a listener
  /// in a background engine would steal events from the background handler.
  static void listen() {
    _sub ??= FlutterCallkitIncoming.onEvent.listen((event) {
      final signal = translate(event);
      if (signal != null && !_signals.isClosed) _signals.add(signal);
    }, onError: (Object e) => Log.w(_tag, 'event stream: $e'));
  }

  /// Android: the isolate entry that receives events while no UI isolate
  /// listens (a Decline on a killed app's notification).
  static Future<void> registerBackgroundHandler(
    Future<void> Function(CallEvent event) handler,
  ) async {
    if (!Platform.isAndroid) return;
    try {
      await FlutterCallkitIncoming.onBackgroundMessage(handler);
    } catch (e) {
      Log.w(_tag, 'background handler: $e');
    }
  }

  // ── Android ringer / ongoing notification ──────────────────────────────

  /// Android only: rings for [data]. False when nothing was shown.
  static Future<bool> showIncoming(
    Map<String, dynamic> data, {
    required String callId,
    required Duration ring,
  }) async {
    if (!Platform.isAndroid || callId.isEmpty) return false;
    try {
      await PushStrings.ensure();
      await FlutterCallkitIncoming.showCallkitIncoming(
        CallKitParamsBuilder.incoming(data, callId: callId, ring: ring),
      );
      _callIdByNativeId[callId] = callId;
      return true;
    } catch (e) {
      Log.w(_tag, 'showIncoming $callId: $e');
      return false;
    }
  }

  /// Android: stop the ringer's sound and notification without ending the
  /// call (our in-app incoming screen took over).
  static Future<void> hideIncoming(String callId) async {
    if (!Platform.isAndroid || callId.isEmpty) return;
    try {
      _hidden.add(callId);
      if (_hidden.length > 20) _hidden.remove(_hidden.first);
      await FlutterCallkitIncoming.hideCallkitIncoming(
        CallKitParamsBuilder.bare(callId),
      );
    } catch (e) {
      Log.w(_tag, 'hideIncoming $callId: $e');
    }
  }

  /// Android: the ongoing-call notification + foreground service (keeps the
  /// mic alive in the background). Same id as the ringer, which it replaces.
  static Future<void> startOngoing(
    String callId, {
    required String name,
    required bool video,
    Map<String, dynamic> extra = const {},
  }) async {
    if (!Platform.isAndroid || callId.isEmpty) return;
    try {
      await PushStrings.ensure();
      final params = CallKitParamsBuilder.ongoing(
        callId,
        name: name,
        video: video,
        extra: extra,
      );
      await FlutterCallkitIncoming.hideCallkitIncoming(params);
      await FlutterCallkitIncoming.startCall(params);
      _callIdByNativeId[callId] = callId;
    } catch (e) {
      Log.w(_tag, 'startOngoing $callId: $e');
    }
  }

  /// Android: ends the plugin call (ringer or ongoing service). The plugin
  /// echoes DECLINE / ENDED for it: callers mark it app-ended first.
  static Future<void> end(String callId) async {
    if (!Platform.isAndroid || callId.isEmpty) return;
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      Log.w(_tag, 'end $callId: $e');
    }
  }

  /// Sign-out: any call left over from a previous process.
  static Future<void> endAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      Log.w(_tag, 'endAll: $e');
    }
  }

  /// Android: the plugin's self-managed Telecom connection for [callId]
  /// goes ACTIVE (until then Telecom treats the call as dialing / ringing
  /// and owns the audio route oddly). The plugin only acts on a call it
  /// already stored, and [startOngoing]'s START broadcast stores it
  /// asynchronously, so this waits (bounded) for the call to show up.
  static Future<void> setConnected(String callId) async {
    if (!Platform.isAndroid || callId.isEmpty) return;
    try {
      for (var i = 0; i < 10; i++) {
        if ((await activeCalls()).any((c) => c.callId == callId)) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await FlutterCallkitIncoming.setCallConnected(callId);
    } catch (e) {
      Log.w(_tag, 'setConnected $callId: $e');
    }
  }

  // ── reads ──────────────────────────────────────────────────────────────

  /// Calls the plugin considers active (Android: the last ones it stored).
  static Future<List<NativeCall>> activeCalls() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return [
        for (final c in calls)
          if (c.id.isNotEmpty) _native(c),
      ];
    } catch (e) {
      Log.w(_tag, 'activeCalls: $e');
      return const [];
    }
  }

  static NativeCall _native(CallKitParams c) {
    final extra = _extra(c.extra);
    final callId = _callIdOf(extra, c.id);
    _remember(callId, c.id);
    return NativeCall(
      nativeId: c.id,
      callId: callId,
      isAccepted: c.isAccepted,
      extra: extra,
    );
  }

  /// The PushKit token (iOS; null elsewhere or when none was issued).
  static Future<String?> voipToken() async {
    if (!Platform.isIOS) return null;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      final s = (token ?? '').trim();
      return s.isEmpty ? null : s;
    } catch (e) {
      Log.w(_tag, 'voipToken: $e');
      return null;
    }
  }

  /// Android 13+ notifications and Android 14 full-screen intent (without
  /// it a call on a locked phone is only a silent notification, E44).
  static Future<void> requestAndroidCallUiPermissions({
    bool fullScreen = true,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await PushStrings.ensure();
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': PushStrings.t('permission.title'),
        'rationaleMessagePermission': PushStrings.t('permission.rationale'),
        'postNotificationMessageRequired': PushStrings.t('permission.settings'),
      });
      if (fullScreen &&
          !await FlutterCallkitIncoming.canUseFullScreenIntent()) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (e) {
      Log.w(_tag, 'call UI permissions: $e');
    }
  }

  // ── translation ────────────────────────────────────────────────────────

  /// A plugin event as a [CallKitSignal] (public: the background isolate
  /// reads events the same way).
  static CallKitSignal? translate(CallEvent? event) => switch (event) {
    CallEventActionCallIncoming(:final callKitParams) => _from(
      CallKitAction.incoming,
      callKitParams,
    ),
    CallEventActionCallStart(:final callKitParams) => _from(
      CallKitAction.started,
      callKitParams,
    ),
    CallEventActionCallAccept(:final callKitParams) => _from(
      CallKitAction.accepted,
      callKitParams,
    ),
    CallEventActionCallDecline(:final callKitParams) => _from(
      CallKitAction.declined,
      callKitParams,
    ),
    CallEventActionCallEnded(:final callKitParams) => _from(
      CallKitAction.ended,
      callKitParams,
    ),
    CallEventActionCallTimeout(:final id) => _byId(CallKitAction.timedOut, id),
    CallEventActionCallConnected(:final id) => _byId(
      CallKitAction.connected,
      id,
    ),
    CallEventActionCallCallback(:final id) => _byId(CallKitAction.callback, id),
    CallEventActionCallToggleAudioSession(:final isActive) => CallKitSignal(
      action: CallKitAction.audioSession,
      flag: isActive,
    ),
    CallEventActionDidUpdateDevicePushTokenVoip() => const CallKitSignal(
      action: CallKitAction.voipTokenUpdated,
    ),
    _ => null,
  };

  static CallKitSignal _from(CallKitAction action, CallKitParams params) {
    final extra = _extra(params.extra);
    final callId = _callIdOf(extra, params.id);
    _remember(callId, params.id);
    return CallKitSignal(
      action: action,
      callId: callId,
      nativeId: params.id,
      extra: extra,
    );
  }

  /// Id-only events: the call id is the plugin id on Android; on iOS only a
  /// UUID seen before maps back (a compliance UUID never does).
  static CallKitSignal _byId(CallKitAction action, String id) => CallKitSignal(
    action: action,
    callId:
        _callIdByNativeId[id] ??
        _callIdByNativeId[id.toLowerCase()] ??
        (Platform.isIOS ? '' : id),
    nativeId: id,
  );

  static void _remember(String callId, String nativeId) {
    if (callId.isEmpty || nativeId.isEmpty) return;
    _callIdByNativeId[nativeId] = callId;
    _callIdByNativeId[nativeId.toLowerCase()] = callId;
  }

  static String _callIdOf(Map<String, dynamic> extra, String nativeId) {
    for (final key in const ['callId', 'call_id']) {
      final v = extra[key]?.toString().trim() ?? '';
      if (v.isNotEmpty && v != 'null') return v;
    }
    final known = _callIdByNativeId[nativeId];
    if (known != null) return known;
    return Platform.isIOS ? '' : nativeId;
  }

  static Map<String, dynamic> _extra(Map<String, dynamic>? raw) =>
      raw == null ? const {} : Map<String, dynamic>.from(raw);
}
