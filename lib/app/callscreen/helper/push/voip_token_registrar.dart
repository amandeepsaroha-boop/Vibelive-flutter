import 'dart:io' show Platform;

import '../../../../core/network/device_info.dart';
import '../../../../core/session/session_store.dart';
import '../../../api/authscreen/push_api.dart';
import '../../../api/authscreen/push_queries.dart';
import '../native/callkit_service.dart';
import 'fcm_token_registrar.dart';

/// The iOS PushKit token: read from the plugin (native stores it at
/// `didUpdate pushCredentials`), kept where login reads it, and sent to
/// `/public-users/:id/voip-token` (the only route that stores it on the
/// user). Re-synced on every plugin token event (E52). Never throws.
abstract final class VoipTokenRegistrar {
  /// Boot: lets `AuthApi` read the token at login (3 × 1.5 s retry) and
  /// stores the current one (the signed-in start syncs it once, later).
  static Future<void> init() async {
    if (!Platform.isIOS) return;
    PushTokens.voipReader = CallKitService.voipToken;
    await refresh(sync: false);
  }

  /// Reads the token again; stores and syncs it when it changed.
  /// [CallKitAction.voipTokenUpdated] and every signed-in start land here.
  static Future<void> refresh({bool sync = true}) async {
    if (!Platform.isIOS) return;
    final token = await CallKitService.voipToken();
    final before = PushTokens.voip;
    if (token == before) return;
    // An invalidated token must not be registered again.
    await PushTokens.saveVoip(token);
    if (sync && token != null) await syncNow();
  }

  /// Sends the stored token for the signed-in user.
  static Future<void> syncNow() async {
    final token = PushTokens.voip;
    if (!Platform.isIOS || token == null) return;
    if (!SessionStore.instance.value.isAuthenticated) return;
    if (PushTokens.fcm != null) {
      // The FCM sync carries the VoIP token too (and the orchestrator).
      await FcmTokenRegistrar.syncIfSignedIn();
      return;
    }
    final deviceId = (await DeviceInfo.get())['deviceId']?.toString();
    await syncVoipToken(token, deviceId: deviceId);
  }
}
