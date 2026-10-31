import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import '../../../../core/utils/log.dart';

/// A one-way line from an Android background isolate to the UI isolate (CE).
///
/// RN ran every handler in one JS context. In Flutter the FCM background
/// isolate has none of the UI isolate's call state, so a `CALL_ENDED` landing
/// there while the UI isolate holds the live call (app backgrounded mid-call)
/// would reach nobody. Two strings, no reply; nothing happens when no UI
/// isolate runs. Both sides still do their own local cleanup.
abstract final class CallIsolateBridge {
  static const portName = 'com.angrymamba.vibelive/call_bridge';
  static const kindEnded = 'ended';
  static const kindAnsweredElsewhere = 'answered_elsewhere';

  /// Talk Now (caller side): the search's pushes, with their payload (JSON)
  /// as the third element — the UI isolate holds the searching call.
  static const kindInstantHostChanged = 'instant_host_changed';
  static const kindInstantConnected = 'instant_connected';
  static const kindInstantFailed = 'instant_failed';

  static ReceivePort? _port;

  /// This isolate is the UI isolate (it hosts the port).
  static bool get isHost => _port != null;

  /// UI isolate only, idempotent. [onMessage] gets the kind, the call id
  /// and the payload (JSON, or null).
  static void host(
    void Function(String kind, String callId, String? payload) onMessage,
  ) {
    if (_port != null) return;
    try {
      // A port left by a previous engine (hot restart, recreated activity)
      // would swallow the message: always claim the name fresh.
      IsolateNameServer.removePortNameMapping(portName);
      final port = ReceivePort();
      if (!IsolateNameServer.registerPortWithName(port.sendPort, portName)) {
        port.close();
        return;
      }
      _port = port;
      port.listen((message) {
        if (message is! List || message.length < 2 || message.length > 3) {
          return;
        }
        final kind = '${message[0]}';
        final callId = '${message[1]}';
        if (callId.isEmpty) return;
        final payload = message.length == 3 && message[2] != null
            ? '${message[2]}'
            : null;
        try {
          onMessage(kind, callId, payload);
        } catch (e) {
          Log.w('CallIsolateBridge', 'handler: $e');
        }
      });
    } catch (e) {
      Log.w('CallIsolateBridge', 'host: $e');
    }
  }

  /// Background isolate → UI isolate. False when no UI isolate listens.
  static bool notifyUi(String kind, String callId, {String? payload}) {
    if (_port != null || callId.isEmpty) return false; // we ARE the UI isolate
    try {
      final port = IsolateNameServer.lookupPortByName(portName);
      if (port == null) return false;
      port.send(payload == null ? [kind, callId] : [kind, callId, payload]);
      return true;
    } catch (_) {
      return false;
    }
  }
}
