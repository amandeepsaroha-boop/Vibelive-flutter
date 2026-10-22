import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../../core/utils/log.dart';

/// `common:push.*` strings for code that has no `BuildContext`: notification
/// copy and the Android call notification, drawn from background isolates
/// too. Loaded from the same asset files i18next reads, in the saved app
/// language (else the device's, else English).
abstract final class PushStrings {
  static const _localeKey = 'app_locale'; // LocaleController's key

  /// The brand, never translated (`common:app_name`).
  static const appName = 'Vibe Live';

  static Map<String, dynamic>? _table;
  static Map<String, dynamic>? _fallback;
  static String? _lang;

  /// Loads the tables once per isolate (and again after a language change).
  static Future<void> ensure() async {
    final lang = _currentLanguage();
    if (_table != null && _lang == lang) return;
    _fallback ??= await _load('en');
    _table = lang == 'en' ? _fallback : (await _load(lang) ?? _fallback);
    _lang = lang;
  }

  /// `push.<key>` with `{{name}}` placeholders filled. English, then the key
  /// itself, when a table is missing.
  static String t(String key, [Map<String, String> vars = const {}]) {
    var text =
        _lookup(_table, key) ?? _lookup(_fallback, key) ?? _english[key] ?? key;
    vars.forEach((k, v) => text = text.replaceAll('{{$k}}', v));
    return text;
  }

  static String _currentLanguage() {
    final saved = AppPrefs.getString(_localeKey);
    final device = PlatformDispatcher.instance.locale.languageCode;
    for (final candidate in [saved, device]) {
      if (candidate != null &&
          AppI18n.supportedLocales.any((l) => l.languageCode == candidate)) {
        return candidate;
      }
    }
    return AppI18n.fallbackLocale.languageCode;
  }

  static Future<Map<String, dynamic>?> _load(String lang) async {
    try {
      final raw = await rootBundle.loadString('assets/i18n/$lang/common.json');
      final json = jsonDecode(raw);
      final push = json is Map ? json['push'] : null;
      return push is Map ? Map<String, dynamic>.from(push) : null;
    } catch (e) {
      Log.w('PushStrings', 'no $lang strings: $e');
      return null;
    }
  }

  static String? _lookup(Map<String, dynamic>? table, String key) {
    Object? node = table;
    for (final part in key.split('.')) {
      if (node is! Map) return null;
      node = node[part];
    }
    return node is String ? node : null;
  }

  /// Last resort when no asset could be read (never shown in practice).
  static const _english = {
    'call.incoming': 'Incoming call',
    'call.incoming_video': 'Incoming video call',
    'call.ongoing_voice': 'Ongoing voice call',
    'call.ongoing_video': 'Ongoing video call',
    'call.end_call': 'End Call',
    'call.accept': 'Accept',
    'call.decline': 'Decline',
  };
}
