import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/events/app_events.dart';
import '../../../core/utils/log.dart';
import '../../api/splashscreen/splash_models.dart';
import '../../api/splashscreen/splash_queries.dart';

/// RN `updateNotice`: whether to show the "new update" notice, decided once
/// per process from `/app-config` (`latest_android_version` /
/// `latest_ios_version`) against the installed build.
///
/// RN's rule: prompt whenever the versions DIFFER (not only when the store
/// is newer), so the backend's version must be raised with each release.
/// "Later" is remembered for the rest of the process; a high-priority /
/// force update has no "Later".
abstract final class UpdateCheck {
  static const _tag = 'UpdateNotice';

  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.angrymamba.VibeLive';
  static const appStoreUrl = 'https://apps.apple.com/app/vibelive/id6759444623';

  static AppVersionInfo? _cached;
  static bool dismissed = false;

  /// The notice to show, or null. Never throws: a failed fetch shows
  /// nothing and is tried again on the next call.
  static Future<AppVersionInfo?> pending() async {
    if (dismissed) return null;
    try {
      final latest = _cached ??= (await ensureAppConfig()).latestVersion;
      if (latest == null) return null;
      final installed = (await PackageInfo.fromPlatform()).version;
      final prompt = latest.shouldPrompt(installed);
      // Once per launch: when the notice fails to appear on a device, this
      // says why.
      Log.w(_tag, 'installed=$installed api=${latest.version} prompt=$prompt');
      return prompt ? latest : null;
    } catch (e) {
      Log.w(_tag, 'app-config check failed: $e');
      return null;
    }
  }

  static Future<void> openStore() async {
    AppEvents.updateTapped(
      version: _cached?.version,
      forced: _cached?.isForceUpdate,
    );
    final url = Uri.parse(Platform.isIOS ? appStoreUrl : playStoreUrl);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.w(_tag, "couldn't open the store: $e");
    }
  }
}
