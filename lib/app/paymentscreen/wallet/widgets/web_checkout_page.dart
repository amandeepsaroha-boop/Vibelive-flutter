import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/analytics/events/payment_events.dart';
import '../../../../core/analytics/screen_tracker.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/log.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/wallet_palette.dart';
import '../helper/web_checkout.dart';

/// RN WalletScreen's WebView modal: "Complete Payment" with a close button
/// over the checkout page (Razorpay when the native checkout could not
/// open, or PayU's hosted form). Pops with how it ended.
class WebCheckoutPage extends StatefulWidget {
  const WebCheckoutPage({super.key, required this.request});

  final WebCheckoutRequest request;

  static Future<WebCheckoutEnd> open(
    BuildContext context,
    WebCheckoutRequest request,
  ) async {
    final end = await Navigator.of(context).push<WebCheckoutEnd>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WebCheckoutPage(request: request),
      ),
    );
    return end ?? const WebCheckoutClosed();
  }

  @override
  State<WebCheckoutPage> createState() => _WebCheckoutPageState();
}

class _WebCheckoutPageState extends State<WebCheckoutPage> {
  static const _tag = 'WebCheckout';

  late final WebViewController _web;
  final _loading = ValueNotifier(true);
  Timer? _poll;
  bool _done = false;

  /// Analytics: PayU's hosted form polls; the Razorpay page does not.
  String get _kind => widget.request.poll != null ? 'payu' : 'razorpay';

  @override
  void initState() {
    super.initState();
    PaymentEvents.webCheckoutOpened(kind: _kind);
    ScreenTracker.view('web_checkout', {'kind': _kind});
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        WebCheckoutPages.channel,
        onMessageReceived: (m) {
          final end = WebCheckoutPages.fromMessage(m.message);
          // RN handled the result 100 ms later, after the modal closed.
          if (end != null) _finish(end);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _loading.value = false,
          onNavigationRequest: (request) {
            final end = WebCheckoutPages.fromUrl(request.url);
            if (end == null) return NavigationDecision.navigate;
            _finish(end);
            return NavigationDecision.prevent;
          },
        ),
      );
    // RN: no cache, incognito.
    unawaited(_load());
    _startPolling();
  }

  Future<void> _load() async {
    try {
      await _web.clearCache();
      await _web.clearLocalStorage();
    } catch (_) {}
    await _web.loadHtmlString(widget.request.html);
  }

  /// RN PayU polling: every 5 s for 5 minutes, the transaction's status.
  void _startPolling() {
    final poll = widget.request.poll;
    if (poll == null) return;
    final until = DateTime.now().add(WebCheckoutRequest.pollFor);
    var busy = false;
    _poll = Timer.periodic(WebCheckoutRequest.pollEvery, (timer) async {
      if (DateTime.now().isAfter(until)) {
        timer.cancel();
        return;
      }
      if (busy) return;
      busy = true;
      try {
        final end = await poll();
        if (end != null) _finish(end, polled: true);
      } catch (e) {
        Log.d(_tag, 'poll failed: $e');
      } finally {
        busy = false;
      }
    });
  }

  void _finish(WebCheckoutEnd end, {bool polled = false}) {
    if (_done || !mounted) return;
    _done = true;
    _poll?.cancel();
    final (result, reason) = switch (end) {
      WebCheckoutPaid() => ('paid', null),
      WebCheckoutFailed(:final reason) => ('failed', reason),
      WebCheckoutClosed() => ('closed', null),
    };
    PaymentEvents.webCheckoutEnded(
      kind: _kind,
      result: polled ? 'polled_$result' : result,
      reason: reason,
    );
    Navigator.of(context).pop(end);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _loading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(const WebCheckoutClosed());
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.ms, 12.ms, 16.ms, 12.ms),
                child: Row(
                  children: [
                    Pressable(
                      onPressed: () => _finish(const WebCheckoutClosed()),
                      semanticLabel: context.t('actions.close'),
                      hitPadding: EdgeInsets.all(8.ms),
                      child: Container(
                        width: 40.ms,
                        height: 40.ms,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: p.soft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(LucideIcons.x, size: 20.ms, color: p.text),
                      ),
                    ),
                    SizedBox(width: 14.ms),
                    Expanded(
                      child: CText(
                        'payment:web_checkout.title',
                        size: 18,
                        weight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: p.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(controller: _web),
                    ValueListenableBuilder<bool>(
                      valueListenable: _loading,
                      builder: (_, loading, _) => loading
                          ? Center(
                              child: CircularProgressIndicator(color: p.accent),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
