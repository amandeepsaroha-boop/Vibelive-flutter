import 'dart:io' show Platform;

import '../../../core/network/strapi.dart';

/// `/app-config` (single type). Thin wrapper: [raw] keeps every field, the
/// getters cover what the app reads today.
class AppConfig {
  const AppConfig(this.raw);

  final JsonMap raw;

  factory AppConfig.fromResponse(dynamic body) =>
      AppConfig(Strapi.map(Strapi.body(body)) ?? const {});

  factory AppConfig.fromJson(Object? json) =>
      AppConfig(Map<String, dynamic>.from(json! as Map));

  JsonMap toJson() => raw;

  String get agoraAppId =>
      J.str(raw['Agora_App_Id']) ?? J.str(raw['agoraAppId']) ?? '';

  JsonMap? get expertPingConfig => Strapi.map(raw['expert_ping_config']);

  /// Latest store version for this platform (`latest_android_version` /
  /// `latest_ios_version`; tolerates a repeatable component).
  AppVersionInfo? get latestVersion {
    final node = Strapi.node(
      raw[Platform.isAndroid ? 'latest_android_version' : 'latest_ios_version'],
    );
    final first = node is List ? (node.isEmpty ? null : node.first) : node;
    final map = Strapi.map(first);
    if (map == null || J.str(map['version']) == null) return null;
    return AppVersionInfo(map);
  }
}

class AppVersionInfo {
  const AppVersionInfo(this.raw);

  final JsonMap raw;

  String get version => J.str(raw['version']) ?? '';
  String? get title => J.str(raw['title']);
  String? get content => J.str(raw['content']) ?? J.str(raw['description']);

  bool get isForceUpdate =>
      (J.str(raw['priority']) ?? '').toLowerCase() == 'high' ||
      J.boolean(raw['isForceUpdate']) ||
      J.boolean(raw['forceUpdate']);

  /// RN rule: prompt whenever the versions *differ* (not only when newer),
  /// ignoring trailing zero segments (3.0 == 3.0.0).
  bool shouldPrompt(String? installedVersion) {
    final current = normalize(installedVersion);
    final latest = normalize(version);
    return current != null && latest != null && current != latest;
  }

  static String? normalize(String? v) {
    final clean = (v ?? '').replaceAll(RegExp(r'[^0-9.]'), '');
    if (clean.isEmpty) return null;
    final parts = clean.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length > 1 && parts.last == 0) {
      parts.removeLast();
    }
    return parts.join('.');
  }
}
