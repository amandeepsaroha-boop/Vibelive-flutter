import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/analytics/events/app_events.dart';
import '../../../core/analytics/events/auth_events.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/log.dart';
import '../../api/authscreen/auth_queries.dart';
import '../../api/authscreen/referrer_api.dart';
import 'deep_links.dart';
import 'link_parser.dart';

enum ReferralStatus { idle, checking, valid, invalid }

/// Referral code of the sign-in screen (RN `LoginScreen` referral state):
/// capture from a link or the Play install referrer, live validation, the
/// `-R` / `-I` suffix the backend needs, and the host to open after login.
class LoginReferral {
  LoginReferral(Map<String, String> routeParams) {
    _capture(routeParams);
  }

  final code = TextEditingController();
  final open = ValueNotifier(false);
  final status = ValueNotifier(ReferralStatus.idle);
  final referrerName = ValueNotifier<String?>(null);

  /// Code that came from a link / install referrer, with its intent.
  ReferralCapture? _captured;
  bool _disposed = false;
  Timer? _debounce, _referrerDelay;

  /// Where the code in the field came from (analytics): `typed`, `link`,
  /// `install_referrer`.
  String _source = 'typed';

  void show() {
    if (!open.value) AuthEvents.referralFieldOpened();
    open.value = true;
  }

  /// Typed code: re-validated 800 ms after the last keystroke.
  void onChanged(String text) {
    _source = 'typed';
    _debounce?.cancel();
    status.value = ReferralStatus.idle;
    referrerName.value = null;
    if (text.trim().isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 800), () => _validate(text));
  }

  /// The UI shows the pure code; the backend needs `CODE-R` / `CODE-I` when
  /// it came from a link with that intent.
  String? backendCode() {
    final clean = code.text.trim();
    if (clean.isEmpty) return null;
    final captured = _captured;
    return captured != null &&
            clean.toUpperCase() == captured.handler.toUpperCase()
        ? '$clean${captured.intent.suffix}'
        : clean;
  }

  /// Expert to open after sign-in when the captured code belongs to one
  /// (RN install-referrer routing). Never throws.
  Future<String?> hostToOpen() async {
    final captured = _captured;
    final handler = captured?.handler ?? code.text.trim();
    if (captured == null || handler.isEmpty) return null;
    try {
      final target = await resolveReferrerTarget(handler);
      return target != null && target.isExpert ? target.documentId : null;
    } catch (e) {
      Log.w('Login', 'referrer routing skipped: $e');
      return null;
    }
  }

  /// Route params > link opened before sign-in > Play install referrer.
  void _capture(Map<String, String> params) {
    for (final raw in [
      params['referral'] ?? params['code'],
      DeepLinks.instance.takeReferral(),
    ]) {
      if (raw == null || LinkParser.isTechnical(raw)) continue;
      final capture = LinkParser.splitHandler(raw);
      if (capture.handler.isNotEmpty) return _apply(capture, source: 'link');
    }
    // Deferred like RN: the Play referrer client needs a moment after launch.
    _referrerDelay = Timer(const Duration(seconds: 1), () async {
      final capture = await DeepLinks.instance.installReferrer();
      AppEvents.installReferrer(
        hasCode: capture != null && capture.handler.isNotEmpty,
        intent: capture?.intent.name,
      );
      if (capture != null && !_disposed) {
        _apply(capture, source: 'install_referrer');
      }
    });
  }

  void _apply(ReferralCapture capture, {required String source}) {
    _captured = capture;
    _source = source;
    // A plain profile link opens the host after login; it is not a code.
    if (capture.intent == ReferralIntent.hostProfile) return;
    code.text = capture.handler.toUpperCase();
    open.value = true;
    _validate(code.text);
  }

  Future<void> _validate(String value) async {
    if (!_disposed) status.value = ReferralStatus.checking;
    ReferralStatus result;
    String? name;
    try {
      final check = await ReferrerApi.validateCode(value);
      result = check.isValid ? ReferralStatus.valid : ReferralStatus.invalid;
      name = check.isValid ? check.referrerName : null;
    } on ApiException catch (_) {
      result = ReferralStatus.invalid;
    }
    // Ignore an answer for a code the user has since changed.
    if (_disposed ||
        ReferrerApi.normalizeCode(code.text) !=
            ReferrerApi.normalizeCode(value)) {
      return;
    }
    status.value = result;
    referrerName.value = name;
    AuthEvents.referralChecked(
      valid: result == ReferralStatus.valid,
      source: _source,
    );
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _referrerDelay?.cancel();
    code.dispose();
    open.dispose();
    status.dispose();
    referrerName.dispose();
  }
}
