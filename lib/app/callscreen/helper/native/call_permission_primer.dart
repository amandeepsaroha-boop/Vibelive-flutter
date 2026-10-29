import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/analytics/events/call_ui_events.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../../core/utils/log.dart';
import '../call_controller.dart';
import '../push/push_session.dart';

/// Runtime permissions the call layer asks for outside a call's own gate.
///
/// - Experts receive calls, often from the lock screen where no prompt can
///   show: mic and camera are asked once, after sign-in, with the app in
///   front (spec §4.1 `primePermissions`, A2).
/// - Android 12+ `BLUETOOTH_CONNECT` (A-extra): without it neither Agora
///   nor Telecom can route the call to a headset. Asked with the call
///   permissions (expert priming, a placed call), once.
///
/// Never throws, never prompts during a call or in the background.
abstract final class CallPermissionPrimer {
  static const _primedKey = 'push_call_perms_primed_v1';
  static const _bluetoothKey = 'push_bt_connect_asked_v1';
  static bool _running = false;

  /// After sign-in and on every resume: a no-op once done.
  static Future<void> primeIfExpert() async {
    if (_running || AppPrefs.getString(_primedKey) != null) return;
    if (!PushSession.isSignedIn || !PushSession.isExpert) return;
    if (!_inFront() || CallController.instance.isOnCall) return;
    _running = true;
    try {
      await AppPrefs.setString(_primedKey, '1');
      final result = await [Permission.microphone, Permission.camera].request();
      CallUiEvents.permissionPrimed(
        mic: result[Permission.microphone]?.isGranted ?? false,
        camera: result[Permission.camera]?.isGranted ?? false,
      );
      await _bluetooth();
    } catch (e) {
      Log.w('CallPermissionPrimer', 'prime: $e');
    } finally {
      _running = false;
    }
  }

  /// A call was placed (the mic gate passed, app in front): Bluetooth
  /// routing, asked once.
  static Future<void> ensureBluetooth() async {
    if (!Platform.isAndroid || _running) return;
    if (AppPrefs.getString(_bluetoothKey) != null) return;
    _running = true;
    try {
      await _bluetooth();
    } catch (e) {
      Log.w('CallPermissionPrimer', 'bluetooth: $e');
    } finally {
      _running = false;
    }
  }

  static Future<void> _bluetooth() async {
    if (!Platform.isAndroid) return;
    // Below Android 12 this reads as granted (install-time permission).
    if (!await Permission.bluetoothConnect.isDenied) return;
    await AppPrefs.setString(_bluetoothKey, '1');
    final status = await Permission.bluetoothConnect.request();
    CallUiEvents.bluetoothPermission(granted: status.isGranted);
  }

  static bool _inFront() {
    try {
      return WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
    } catch (_) {
      return false;
    }
  }
}
