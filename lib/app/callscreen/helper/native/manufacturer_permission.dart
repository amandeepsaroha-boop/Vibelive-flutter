import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../../../../core/storage/app_prefs.dart';
import '../push/push_session.dart';

/// OEMs whose own permission screens decide whether a call shows.
enum CallBrand { xiaomi, samsung, oppo, onePlus }

/// A permission the OEM keeps outside Android's own model.
enum OemPermission {
  showOnLockScreen,
  backgroundPopups,
  appearOnTop,
  fullScreenNotification,
}

/// What the device-permission prompt should show (copy belongs to the UI).
class DevicePermissionCheck {
  const DevicePermissionCheck(this.brand, this.missing);
  final CallBrand brand;
  final List<OemPermission> missing;
}

/// RN `DevicePermissionGate` logic + CE `ManufacturerPermission` channel
/// (`calls/ManufacturerPermission.kt`). Android, experts (hosts) only, once
/// per session, "Don't show again" = 24 h snooze. The widget lives with the
/// UI: it calls [check] (on launch and on resume while shown), [openSettings]
/// and [snooze]. Never throws.
abstract final class DevicePermissionGate {
  static const _channel = MethodChannel(
    'com.angrymamba.vibelive/manufacturer_permission',
  );
  static const snoozeKey = 'PERMISSION_SNOOZE_UNTIL';
  static const oppoGrantedKey = 'OPPO_ONEPLUS_PERM_GRANTED';
  static const snoozeFor = Duration(hours: 24);

  /// MIUI app-ops RN reads by reflection.
  static const _miuiLockScreenOp = 10020;
  static const _miuiPopupOp = 10021;

  static bool _checkedThisSession = false;

  /// Null = nothing to show (not Android, not an expert, snoozed, already
  /// checked this session, another brand, or everything granted). [force]:
  /// a manual trigger ignores the snooze and the session flag.
  static Future<DevicePermissionCheck?> check({bool force = false}) async {
    if (!Platform.isAndroid || !PushSession.isExpert) return null;
    if (_checkedThisSession && !force) return null;
    _checkedThisSession = true;
    if (!force) {
      final until = int.tryParse(AppPrefs.getString(snoozeKey) ?? '');
      if (until != null && DateTime.now().millisecondsSinceEpoch < until) {
        return null;
      }
    }
    final brand = await _brand();
    if (brand == null) return null;
    final missing = <OemPermission>[];
    switch (brand) {
      case CallBrand.xiaomi:
        if (!await _xiaomi(_miuiLockScreenOp)) {
          missing.add(OemPermission.showOnLockScreen);
        }
        if (!await _xiaomi(_miuiPopupOp)) {
          missing.add(OemPermission.backgroundPopups);
        }
      case CallBrand.samsung:
        if (!await _bool('canDrawOverlays')) {
          missing.add(OemPermission.appearOnTop);
        }
      case CallBrand.oppo:
      case CallBrand.onePlus:
        // Unreadable on ColorOS / OxygenOS: self-reported (RN).
        if (AppPrefs.getString(oppoGrantedKey) != 'true') {
          missing.addAll(const [
            OemPermission.fullScreenNotification,
            OemPermission.showOnLockScreen,
          ]);
        }
    }
    return missing.isEmpty ? null : DevicePermissionCheck(brand, missing);
  }

  /// "Enable permissions": the brand's own settings page.
  static Future<void> openSettings(CallBrand brand) async {
    switch (brand) {
      case CallBrand.xiaomi:
        await _invoke('openXiaomiPermissions');
      case CallBrand.samsung:
        await _invoke('openSamsungOverlaySettings');
      case CallBrand.oppo:
      case CallBrand.onePlus:
        await AppPrefs.setString(oppoGrantedKey, 'true');
        await _invoke('openAppSettings');
    }
  }

  /// "Don't show again" (24 h).
  static Future<void> snooze() => AppPrefs.setString(
    snoozeKey,
    '${DateTime.now().add(snoozeFor).millisecondsSinceEpoch}',
  );

  static Future<CallBrand?> _brand() async {
    final info = await _invoke('manufacturer');
    if (info is! Map) return null;
    final maker = '${info['manufacturer'] ?? ''}'.toLowerCase();
    final brand = '${info['brand'] ?? ''}'.toLowerCase();
    if (maker.contains('xiaomi') ||
        maker.contains('redmi') ||
        brand.contains('poco')) {
      return CallBrand.xiaomi;
    }
    if (maker.contains('samsung')) return CallBrand.samsung;
    if (maker.contains('oppo') || brand.contains('oppo')) return CallBrand.oppo;
    if (maker.contains('oneplus') || brand.contains('oneplus')) {
      return CallBrand.onePlus;
    }
    return null;
  }

  /// A failed read counts as granted (RN): never a prompt by mistake.
  static Future<bool> _xiaomi(int op) async =>
      await _invoke('checkXiaomiPermission', op) != false;

  static Future<bool> _bool(String method) async =>
      await _invoke(method) != false;

  static Future<Object?> _invoke(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, args);
    } catch (_) {
      return null;
    }
  }
}
