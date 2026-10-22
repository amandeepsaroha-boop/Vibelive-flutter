import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../storage/app_prefs.dart';
import '../utils/log.dart';

/// `deviceInfo` payload sent with OTP verify / social login / refresh
/// (RN `resolveDeviceInfo`). Resolved once, then cached.
abstract final class DeviceInfo {
  static const _installIdKey = 'install_id';
  static Map<String, dynamic>? _cached;

  static String get platform => Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
      ? 'android'
      : 'unknown';

  static Future<Map<String, dynamic>> get() async {
    final cached = _cached;
    if (cached != null) return cached;

    String model = '$platform-device';
    String? appVersion;
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await plugin.iosInfo;
        model = ios.utsname.machine;
      } else if (Platform.isAndroid) {
        final android = await plugin.androidInfo;
        model = '${android.manufacturer} ${android.model}';
      }
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (e, st) {
      Log.e('DeviceInfo', e, st);
    }

    return _cached = {
      'deviceId': '$platform-${_installId()}',
      'model': model,
      'platform': platform,
      'appVersion': appVersion,
    };
  }

  /// Stable per install (RN used a per-launch session id).
  static String _installId() {
    final existing = AppPrefs.getString(_installIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    AppPrefs.setString(_installIdKey, id);
    return id;
  }
}
