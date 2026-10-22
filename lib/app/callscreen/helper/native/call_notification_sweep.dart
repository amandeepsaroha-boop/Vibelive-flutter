import 'dart:io' show Platform;

import '../push/local_notifier.dart';

/// Clears the call notifications nobody owns once a call is over (CE port of
/// RN `clearCallNotifications`, E46). The backend sends `CallTimer` as an FCM
/// notification ("Ongoing Call / Call started"); Android draws it itself
/// whenever the app is not in front, so no app code posted it and none
/// removes it.
///
/// The plugin's ringing and missed-call channels are left alone. Android
/// only; never throws.
abstract final class CallNotificationSweep {
  static const _protected = {
    'callkit_incoming_channel_id_v2',
    'callkit_incoming_channel_id',
    'callkit_missed_channel_id',
  };

  /// RN `CALL_KEYWORDS` minus the bare "call" / "calling".
  static const _keywords = [
    'ongoing call',
    'call in progress',
    'call started',
    'caller has started',
    'incoming call',
    'is calling',
  ];

  static Future<void> clearEnded() async {
    if (!Platform.isAndroid) return;
    try {
      for (final n in await LocalNotifier.active()) {
        if (_protected.contains(n.channelId)) continue;
        final text = '${n.title ?? ''} ${n.body ?? ''}'.toLowerCase();
        final isCall =
            n.channelId == 'callkit_ongoing_channel_id' ||
            (text.trim().isNotEmpty && _keywords.any(text.contains));
        if (isCall) await LocalNotifier.cancelActive(n);
      }
    } catch (_) {}
  }
}
