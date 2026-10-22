import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/session/session_store.dart';
import '../../../../core/utils/log.dart';
import '../../../api/client/client_queries.dart';
import '../../../api/listingflow/listing_models.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../../../component/app_share.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_toast.dart';
import 'host_profile_rules.dart';

/// What the profile sheet does besides drawing (RN `ProfileModal` logic): the
/// pre-call checks before a call is handed off, and the share link.
///
/// State is split into small notifiers so only the piece showing it
/// rebuilds: the photo index, the call buttons' busy state, the status bar.
class HostProfileController {
  HostProfileController({
    required this.close,
    required this.navigate,
    required this.confirmStart,
    required this.handOff,
  });

  /// Closes the profile sheet.
  final VoidCallback close;

  /// Opens [route] (called right after [close]).
  final void Function(String route) navigate;

  /// The safety notice shown before connecting; true = start the call.
  final Future<bool> Function(bool video) confirmStart;

  /// The call layer (`startOutgoingCall`).
  final Future<void> Function(HostCard host, bool video) handOff;

  /// Gallery photo shown in the hero.
  final activeImage = ValueNotifier(0);

  /// From the tap until the call is handed off (RN `preparingCall`).
  final preparingCall = ValueNotifier(false);

  /// The photo has scrolled under the status bar.
  final pastHero = ValueNotifier(false);

  static const _tag = 'HostProfile';

  // Sync guard: two taps in the same frame must not both get through.
  bool _callLock = false;
  bool _disposed = false;

  void nextImage(int count) {
    if (count > 1) activeImage.value = (activeImage.value + 1) % count;
  }

  void previousImage(int count) {
    if (count > 1) {
      activeImage.value = (activeImage.value - 1 + count) % count;
    }
  }

  /// Scroll offset of the profile list (status bar style).
  void onScroll(double pixels, double heroEnd) =>
      _set(pastHero, pixels > heroEnd);

  /// OS share sheet with RN's message ("Check out … on Vibe: link").
  Future<void> share(BuildContext context, HostCard host) => AppShare.text(
    context.t(
      'host:share.message',
      variables: {'name': host.name, 'url': HostProfileRules.shareUrl(host)},
    ),
    anchor: context.findRenderObject(),
  );

  Future<void> copyLink(HostCard host) async {
    await Clipboard.setData(
      ClipboardData(text: HostProfileRules.shareUrl(host)),
    );
    CToast.show('host:share.copied', variant: CToastVariant.success);
  }

  /// Audio / video button: every RN check in order, then the hand-off.
  /// Which call button started the current [preparingCall] (spinner).
  bool pendingVideo = false;

  Future<void> placeCall(
    HostCard host, {
    required bool video,
    required bool isMe,
    required bool isCompany,
  }) async {
    if (_callLock) return;
    _callLock = true;
    _set(preparingCall, true);
    var handedOff = false;
    try {
      handedOff = await _check(host, video, isMe, isCompany);
    } finally {
      _callLock = false;
      // Handed off: the sheet is closing, keep the spinner (RN).
      if (!handedOff) _set(preparingCall, false);
    }
  }

  Future<bool> _check(
    HostCard host,
    bool video,
    bool isMe,
    bool isCompany,
  ) async {
    if (isMe) {
      await CAlert.show(
        title: 'host:call.self_title',
        message: 'host:call.self_message',
      );
      return false;
    }

    final uid = SessionStore.instance.value.userDocumentId;
    if (uid == null) {
      final login = await CAlert.show(
        title: 'host:call.login_title',
        message: 'host:call.login_message',
        primaryLabel: 'host:call.login',
        secondaryLabel: 'actions.cancel',
        variant: CAlertVariant.warning,
      );
      if (login == true) _leaveTo(AppRoutes.login);
      return false;
    }

    // Started now so it overlaps the profile read. A failed read lets the
    // call through (RN fails open: the wallet never blocks a call).
    final wallet = ensureWalletBalance(userDocumentId: uid)
        .then<WalletBalance?>(
          (balance) => balance,
          onError: (Object e) {
            Log.w(_tag, 'balance read failed, calling anyway: $e');
            return null;
          },
        );

    var company = isCompany;
    try {
      final me = await ensureMyProfile(uid);
      company = company || me.isCompanyAccount;
      if (me.name == null || me.email == null || me.mobile == null) {
        if (_disposed) return false;
        final update = await CAlert.show(
          title: 'host:call.incomplete_title',
          message: 'host:call.incomplete_message',
          primaryLabel: 'host:call.update_profile',
          secondaryLabel: 'actions.cancel',
          variant: CAlertVariant.warning,
        );
        if (update == true) _leaveTo(AppRoutes.personalInfo);
        return false;
      }
    } on ApiException catch (e) {
      // RN: a failed profile read never blocks the call.
      Log.w(_tag, 'profile check skipped: $e');
    }

    final rate = video ? host.vPrice : host.aPrice;
    if (!company && rate > 0) {
      final balance = await wallet;
      final required = rate * HostProfileRules.minCallMinutes;
      if (balance != null && balance.cashBalance < required) {
        if (_disposed) return false;
        final earnings = balance.earningsBalance;
        final go = await CAlert.show(
          title: 'host:call.low_balance_title',
          message: earnings > 0
              ? 'host:call.low_balance_earnings'
              : 'host:call.low_balance_message',
          variables: {
            'cash': HostProfileRules.money(balance.cashBalance),
            'required': HostProfileRules.money(required),
            'minutes': HostProfileRules.minCallMinutes,
            'rate': HostProfileRules.price(rate),
            'earnings': HostProfileRules.money(earnings),
          },
          primaryLabel: earnings > 0
              ? 'host:call.transfer'
              : 'host:call.recharge',
          secondaryLabel: 'actions.cancel',
          variant: CAlertVariant.warning,
        );
        // Earnings move to cash on the wallet screen.
        if (go == true) _leaveTo(AppRoutes.wallet);
        return false;
      }
    }

    if (_disposed || !await confirmStart(video) || _disposed) return false;
    close();
    await handOff(host, video);
    return true;
  }

  void _leaveTo(String route) {
    if (_disposed) return;
    close();
    navigate(route);
  }

  void _set<T>(ValueNotifier<T> notifier, T value) {
    if (!_disposed) notifier.value = value;
  }

  void dispose() {
    _disposed = true;
    activeImage.dispose();
    preparingCall.dispose();
    pastHero.dispose();
  }
}
