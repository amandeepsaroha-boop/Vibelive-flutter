import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android notification channels (spec_call_native §4.6). The RN channel ids
/// are kept, so users' per-channel settings survive the RN → Flutter update
/// (same applicationId). Names are fixed English, as in RN.
///
/// Call channels belong to `flutter_callkit_incoming`
/// (`callkit_incoming_channel_id_v2`, `callkit_ongoing_channel_id`,
/// `callkit_missed_channel_id`); their names come from `AndroidParams`.
abstract final class NotificationChannels {
  static const general = 'default';
  static const campaigns = 'vibe_campaigns';
  static const verification = 'verification_updates';
  static const walletTransfersCredit = 'wallet_transfers_credit_v3';
  static const walletTransfers = 'wallet_transfers_v2';
  static const walletTopup = 'wallet_topup_v3';

  /// Legacy RN notifee / native ids, deleted on every start.
  static const legacyIds = [
    'incoming_calls_ringing_v10',
    'incoming_calls_inapp_v3',
    'incoming_calls_vibe_v3',
    'ongoing_calls_vibe_v2',
  ];

  static const _coin = RawResourceAndroidNotificationSound('coin_sound_add');

  static const channels = <AndroidNotificationChannel>[
    AndroidNotificationChannel(
      general,
      'General Notifications',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      campaigns,
      'Offers & Updates',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      verification,
      'Verification & Profile Updates',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      walletTransfersCredit,
      'Wallet Transfers (Credit)',
      importance: Importance.high,
      sound: _coin,
    ),
    AndroidNotificationChannel(
      walletTransfers,
      'Wallet Transfers',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      walletTopup,
      'Wallet Top Up',
      importance: Importance.high,
      sound: _coin,
    ),
  ];

  static String nameOf(String id) =>
      channels.firstWhere((c) => c.id == id, orElse: () => channels.first).name;

  /// Channels whose notifications are drawn with the coin sound.
  static AndroidNotificationSound? soundOf(String id) =>
      channels.where((c) => c.id == id).firstOrNull?.sound;

  /// Idempotent; Android only. Never throws.
  static Future<void> ensure(FlutterLocalNotificationsPlugin plugin) async {
    if (!Platform.isAndroid) return;
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final id in legacyIds) {
      try {
        await android.deleteNotificationChannel(channelId: id);
      } catch (_) {}
    }
    for (final channel in channels) {
      try {
        await android.createNotificationChannel(channel);
      } catch (_) {}
    }
  }
}
