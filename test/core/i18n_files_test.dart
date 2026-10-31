import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/core/i18n/i18n.dart';

/// Every app language has every namespace English has, with the same keys
/// and placeholders, and is bundled (pubspec). A missing key would show the
/// English text; a broken `{{placeholder}}` would show the raw braces.
void main() {
  const root = 'assets/i18n';
  final namespaces = [
    for (final f in Directory('$root/en').listSync())
      if (f.path.endsWith('.json')) f.uri.pathSegments.last,
  ]..sort();
  final placeholder = RegExp(r'\{\{[^}]+\}\}');

  Map<String, dynamic> read(String lang, String ns) =>
      jsonDecode(File('$root/$lang/$ns').readAsStringSync())
          as Map<String, dynamic>;

  List<String> placeholdersOf(Map<String, dynamic> node) => [
    for (final v in node.values)
      if (v is String) ...placeholder.allMatches(v).map((m) => m[0]!),
  ]..sort();

  /// Differences between [en] and [tr] under [path]. Placeholders are
  /// compared per object: split strings (lead / accent) may move one
  /// between their halves for word order.
  void compare(Object? en, Object? tr, String path, List<String> problems) {
    if (en is Map<String, dynamic>) {
      if (tr is! Map<String, dynamic>) {
        problems.add('$path: not an object');
        return;
      }
      for (final k in en.keys) {
        if (!tr.containsKey(k)) problems.add('$path.$k: missing');
      }
      for (final k in tr.keys) {
        if (!en.containsKey(k)) problems.add('$path.$k: not in English');
      }
      if (!listEquals(placeholdersOf(en), placeholdersOf(tr))) {
        problems.add('$path: placeholders differ');
      }
      for (final k in en.keys) {
        if (tr.containsKey(k)) compare(en[k], tr[k], '$path.$k', problems);
      }
    } else if (en is String) {
      if (tr is! String) {
        problems.add('$path: not a string');
      } else if (en.trim().isNotEmpty && tr.trim().isEmpty) {
        problems.add('$path: empty');
      }
    } else if (en is List) {
      if (tr is! List || tr.length != en.length) {
        problems.add('$path: list length differs');
      } else {
        for (var i = 0; i < en.length; i++) {
          compare(en[i], tr[i], '$path[$i]', problems);
        }
      }
    }
  }

  test('the language list matches the supported locales', () {
    final codes = AppI18n.languages.map((l) => l.code).toList();
    expect(codes.toSet(), hasLength(codes.length), reason: 'unique codes');
    expect(codes.first, 'en');
    expect(AppI18n.supportedLocales.map((l) => l.languageCode), codes);
    expect(AppI18n.languageOf(const Locale('ta')).nativeName, 'தமிழ்');
    expect(AppI18n.languageOf(const Locale('xx')).code, 'en');
  });

  test('every language is bundled in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final l in AppI18n.languages) {
      expect(pubspec, contains('- assets/i18n/${l.code}/'), reason: l.code);
    }
  });

  for (final lang in AppI18n.languages.where((l) => l.code != 'en')) {
    test('${lang.englishName} (${lang.code}): every key of English', () {
      final problems = <String>[];
      for (final ns in namespaces) {
        if (!File('$root/${lang.code}/$ns').existsSync()) {
          problems.add('$ns: missing file');
          continue;
        }
        compare(read('en', ns), read(lang.code, ns), ns, problems);
      }
      expect(problems, isEmpty, reason: problems.take(20).join('\n'));
    });
  }
}
