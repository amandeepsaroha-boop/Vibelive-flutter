import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../../core/router/app_router.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../component/app_share.dart';

/// What the ME tab does outside its own widgets: open screens, share.
abstract final class MeActions {
  /// Opens a screen; on return, quietly re-reads the profile (RN re-read ME
  /// on every focus: a user comes back from Professional Details a host).
  static Future<void> open(BuildContext context, String route) async {
    if (route == AppRoutes.wallet) prefetchWalletTransactions();
    await context.push<void>(route);
    revalidate();
  }

  /// Re-reads my profile unless it is fresh; failures keep what is shown.
  static void revalidate() {
    final id = SessionStore.instance.value.userDocumentId;
    if (id == null) return;
    ensureMyProfile(id).ignore();
  }

  /// The OS share sheet (copies the text if it can't open). [contentType]:
  /// what is shared, for analytics.
  static Future<void> share(String text, {String contentType = 'text'}) =>
      AppShare.text(text, contentType: contentType);

  /// Analytics name of a ME row: the last part of its i18n key
  /// (`client:me.items.personal` → `personal`) or of its route.
  static String itemName(String keyOrRoute) {
    final source = keyOrRoute.startsWith('/')
        ? Uri.parse(keyOrRoute).path
        : keyOrRoute;
    final last = source
        .split(RegExp(r'[.:/]'))
        .lastWhere((p) => p.isNotEmpty, orElse: () => source);
    return last.replaceAll('-', '_');
  }

  static Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// Straight into WhatsApp. `whatsapp://` first, then the `wa.me` universal
  /// link (still lands in the app when the scheme is unavailable); false
  /// when neither opens.
  static Future<bool> openWhatsApp(String text) async {
    final encoded = Uri.encodeComponent(text);
    for (final url in [
      'whatsapp://send?text=$encoded',
      'https://wa.me/?text=$encoded',
    ]) {
      try {
        if (await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        )) {
          return true;
        }
      } catch (e) {
        Log.w('Me', 'whatsapp launch failed: $e');
      }
    }
    return false;
  }
}
