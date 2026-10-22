import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/log.dart';
import '../../component/c_alert.dart';

/// Opens a URL; true when something opened it.
typedef UrlOpener = Future<bool> Function(Uri uri, LaunchMode mode);

/// Every link the Resources screens open goes through here, so tests can
/// swap [opener] for a fake.
abstract final class ResourceLinks {
  @visibleForTesting
  static UrlOpener opener = _launch;

  @visibleForTesting
  static void reset() => opener = _launch;

  static Future<bool> _launch(Uri uri, LaunchMode mode) =>
      launchUrl(uri, mode: mode);

  /// `x.com/page` and `www.x.com` get `https://`; anything else without a
  /// scheme (a relative CMS link) is not openable.
  static Uri? parse(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    if (uri.hasScheme) return uri;
    if (RegExp(
      r'^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+([/?#]|$)',
      caseSensitive: false,
    ).hasMatch(value)) {
      return Uri.tryParse('https://$value');
    }
    return null;
  }

  /// Opens without telling the user when it fails.
  static Future<bool> tryOpen(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    try {
      return await opener(uri, mode);
    } catch (e) {
      Log.w('Resources', 'cannot open $uri: $e');
      return false;
    }
  }

  /// A link inside a page or a support contact (RN `Linking.openURL`, with
  /// the "Unable to open link" alert on failure).
  static Future<bool> open(String raw) async {
    final uri = parse(raw);
    final ok = uri != null && await tryOpen(uri);
    if (!ok) {
      await CAlert.show(
        title: 'resources:links.error_title',
        message: 'resources:links.open_failed',
        variant: CAlertVariant.error,
      );
    }
    return ok;
  }

  static String mailto(String email) =>
      Uri(scheme: 'mailto', path: email.trim()).toString();

  static String tel(String phone) =>
      'tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}';

  /// `wa.me` wants the number with country code and digits only.
  static String whatsapp(String number) {
    var digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) digits = '91$digits';
    return 'https://wa.me/$digits';
  }
}
