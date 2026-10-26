import 'package:flutter/widgets.dart' show StringCharacters;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

/// "Enhance with AI" for the tagline and bio. The only place that knows
/// the endpoint and its response shape.
abstract final class HostTextEnhanceApi {
  static const path = '/ai/enhance'; // TODO: confirm with backend

  static const timeout = Duration(seconds: 20);

  /// [text] rewritten by the server, trimmed and cut to [maxLength]
  /// characters. [kind] is `tagline` or `bio`. Throws [ApiException] when
  /// the call fails or the answer is empty.
  static Future<String> enhance(
    String text, {
    required String kind,
    required int maxLength,
  }) async {
    final res = await ApiClient.post(
      path,
      data: {'text': text.trim(), 'type': kind, 'maxLength': maxLength},
      timeout: timeout,
    );
    final out = parse(res);
    if (out.isEmpty) {
      throw ApiException(
        ApiErrorType.parse,
        messageKey: 'hostflow:enhance.failed',
        data: res,
      );
    }
    final chars = out.characters;
    return chars.length <= maxLength
        ? out
        : chars.take(maxLength).toString().trimRight();
  }

  /// The text from `text` / `enhanced` / `result` / `data.text` /
  /// `data.enhanced` (or a plain string body), trimmed; empty if none.
  static String parse(dynamic res) {
    if (res is String) return res.trim();
    if (res is! Map) return '';
    final data = res['data'];
    for (final v in [
      res['text'],
      res['enhanced'],
      res['result'],
      if (data is Map) ...[data['text'], data['enhanced']],
      if (data is String) data,
    ]) {
      final s = v is String ? v.trim() : '';
      if (s.isNotEmpty) return s;
    }
    return '';
  }
}
