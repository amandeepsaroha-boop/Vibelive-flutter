import 'dart:async';

import '../../../../core/query/query_client.dart';
import '../../../../core/storage/app_prefs.dart';
import '../../../api/paymentscreen/payment_keys.dart';
import 'local_notifier.dart';
import 'notification_channels.dart';
import 'push_envelope.dart';
import 'push_strings.dart';

/// What a wallet push should draw.
enum WalletPushKind { topup, transfer, none }

/// RN `walletTransferNotifications.js`: which wallet pushes draw a
/// notification (display), and which taps open the wallet (routing).
abstract final class WalletClassifier {
  static const directTransferTypes = {
    'wallet_transfer',
    'wallet_transaction',
    'transaction',
    'wallet_transfer_credit',
    'wallet_transfer_debit',
    'money_received',
    'money_paid',
    'wallet_credit',
    'wallet_debit',
    'credit',
    'debit',
  };
  static const transferEvents = {
    'money_paid',
    'money_received',
    'wallet_debit',
    'wallet_credit',
    'debit',
    'credit',
    'transfer',
  };
  static const directTopupTypes = {
    'wallet_top_up',
    'wallet_topup',
    'wallet_referral_topup',
    // Bonus credit arrives unprompted: same treatment as a referral credit.
    'wallet_bonus_credit',
    'topup',
  };
  static const skipTypes = {'wallet_update', 'wallet_updated'};

  /// RN `WALLET_TAP_TYPES`.
  static const tapTypes = {
    'wallet',
    ...directTopupTypes,
    ...directTransferTypes,
    ...skipTypes,
  };
  static const tapIdPrefixes = ['wallet_transfer_', 'wallet_topup_'];
  static const tapKeywords = [
    'wallet',
    'topup',
    'top-up',
    'balance',
    'transfer',
    'transaction',
    'money received',
    'money deducted',
    'money paid',
    'money sent',
  ];
  static const transferPhrases = [
    'paid to',
    'received from',
    'sent to',
    'deducted',
    'added',
    'money paid',
    'charged by',
    'money received',
    'money deducted',
  ];

  static String _event(PushEnvelope m) =>
      (m.data['eventType'] ?? m.data['event'] ?? m.data['action'] ?? '')
          .toLowerCase();

  static String _txType(PushEnvelope m) =>
      (m.data['transactionType'] ?? '').toLowerCase();

  static bool isDirectTopup(PushEnvelope m) {
    final event = _event(m);
    return directTopupTypes.contains(m.type) ||
        event == 'topup_success' ||
        event == 'topup' ||
        _txType(m) == 'topup';
  }

  static bool isDirectTransfer(PushEnvelope m) {
    final tx = _txType(m);
    return directTransferTypes.contains(m.type) ||
        transferEvents.contains(_event(m)) ||
        tx == 'debit' ||
        tx == 'credit' ||
        tx == 'transfer';
  }

  /// RN `isWalletLikePayload`.
  static bool isWalletLike(PushEnvelope m) {
    final event = _event(m);
    final d = m.data;
    return m.type == 'wallet' ||
        directTopupTypes.contains(m.type) ||
        directTransferTypes.contains(m.type) ||
        event == 'wallet_update' ||
        event == 'topup_success' ||
        d.containsKey('transactionType') ||
        d.containsKey('balance') ||
        d.containsKey('newBalance') ||
        d.containsKey('walletBalance');
  }

  /// RN `hasExplicitTransferHints`.
  static bool hasTransferHints(PushEnvelope m) {
    if (_txType(m) == 'transfer') return true;
    if (m.data.containsKey('direction')) return true;
    if (m.data.containsKey('counterpartyName')) return true;
    final text = '${m.titleLower} ${m.bodyLower}';
    return transferPhrases.any(text.contains);
  }

  /// RN `matchesWalletTransferTrigger`: a push this module draws (and the
  /// campaign handler must leave alone).
  static bool matchesTransferTrigger(PushEnvelope m) {
    if (isDirectTopup(m) || isDirectTransfer(m)) return true;
    if (skipTypes.contains(m.type)) return false;
    if (!isWalletLike(m)) return false;
    return hasTransferHints(m);
  }

  /// What to draw. The RN "resolve the transfer through two API calls"
  /// fallback is dropped: the backend sends `direction` now.
  static WalletPushKind classify(PushEnvelope m) {
    if (isDirectTopup(m)) return WalletPushKind.topup;
    if (isDirectTransfer(m)) return WalletPushKind.transfer;
    if (skipTypes.contains(m.type)) return WalletPushKind.none;
    if (isWalletLike(m) && hasTransferHints(m)) return WalletPushKind.transfer;
    return WalletPushKind.none;
  }

  /// Any wallet push (draws something or only refreshes the balance).
  static bool isWallet(PushEnvelope m) =>
      classify(m) != WalletPushKind.none ||
      skipTypes.contains(m.type) ||
      isWalletLike(m);

  /// RN `isWalletNotificationTapTarget`, explicit part (ids and types).
  static bool isExplicitTap(PushEnvelope m) {
    final id = (m.notificationId ?? '').toLowerCase();
    if (tapIdPrefixes.any(id.startsWith) || id == 'wallet_update_latest') {
      return true;
    }
    return tapTypes.contains(m.type) || classify(m) != WalletPushKind.none;
  }

  /// RN `isWalletNotificationTapTarget`, keyword part.
  static bool matchesTapKeywords(PushEnvelope m) => tapKeywords.any(
    (k) =>
        m.titleLower.contains(k) ||
        m.bodyLower.contains(k) ||
        m.type.contains(k),
  );
}

/// Draws wallet pushes the way RN did (coin sound on credits and top-ups,
/// 2 s cooldown per kind) and keeps the wallet balance fresh.
abstract final class WalletNotifications {
  static const cooldown = Duration(seconds: 2);

  /// RN `wallet_topup_${Date.now()}`: top-ups stack, none replaces another.
  static String topupId() =>
      'wallet_topup_${DateTime.now().millisecondsSinceEpoch}';

  /// Set by a background isolate; the UI isolate refreshes on resume.
  static const _refreshKey = 'push_wallet_refresh';

  static DateTime? _lastTopup;
  static DateTime? _lastTransfer;

  static Future<void> present(
    PushEnvelope m, {
    required bool background,
  }) async {
    switch (WalletClassifier.classify(m)) {
      case WalletPushKind.topup:
        await _topup(m);
      case WalletPushKind.transfer:
        await _transfer(m);
      case WalletPushKind.none:
        break;
    }
    await requestRefresh(background: background);
  }

  /// The balance is stale. In the UI isolate the wallet queries refetch now;
  /// a background isolate leaves a mark for the next resume.
  static Future<void> requestRefresh({required bool background}) async {
    if (background) {
      await AppPrefs.setString(_refreshKey, '1');
      return;
    }
    _invalidate();
  }

  /// UI isolate, on resume: a background push changed the balance.
  static Future<void> applyPendingRefresh() async {
    if (AppPrefs.getString(_refreshKey) == null) return;
    await AppPrefs.remove(_refreshKey);
    _invalidate();
  }

  static void _invalidate() {
    try {
      queryCache.invalidateAll(const [
        PaymentKeys.wallets,
        PaymentKeys.transactions,
      ]);
    } catch (_) {}
  }

  static Future<void> _topup(PushEnvelope m) async {
    if (_within(_lastTopup)) return;
    _lastTopup = DateTime.now();
    final amount = _money(
      m.data['amount'] ?? m.data['topupAmount'] ?? m.data['value'],
    );
    final title = m.title ?? PushStrings.t('wallet.topup_title');
    final body =
        m.body ??
        (amount == null
            ? PushStrings.t('wallet.topup_body')
            : PushStrings.t('wallet.topup_body_amount', {'amount': amount}));
    final id = topupId();
    await LocalNotifier.show(
      id: id,
      title: title,
      body: body,
      envelope: m.copyWith(
        data: {...m.data, 'type': m.data['type'] ?? 'wallet_top_up'},
        notificationId: id,
      ),
      channelId: NotificationChannels.walletTopup,
      autoCancel: false,
    );
  }

  static Future<void> _transfer(PushEnvelope m) async {
    if (_within(_lastTransfer)) return;
    _lastTransfer = DateTime.now();
    final isCredit = (m.data['direction'] ?? '').toLowerCase() != 'debit';
    final amount = _money(m.data['amount'] ?? m.data['value']);
    final name =
        m.data['counterpartyName'] ??
        m.data['counterparty'] ??
        m.data['name'] ??
        '';
    final title =
        m.title ??
        PushStrings.t(isCredit ? 'wallet.received_title' : 'wallet.paid_title');
    final body = m.body ?? _transferBody(isCredit, amount, name);
    final id =
        'wallet_transfer_${isCredit ? 'credit' : 'debit'}_'
        '${DateTime.now().millisecondsSinceEpoch}';
    await LocalNotifier.show(
      id: id,
      title: title,
      body: body,
      envelope: m.copyWith(
        data: {
          ...m.data,
          'type': 'wallet_transfer',
          'direction': isCredit ? 'credit' : 'debit',
        },
        notificationId: id,
      ),
      channelId: isCredit
          ? NotificationChannels.walletTransfersCredit
          : NotificationChannels.walletTransfers,
      autoCancel: false,
    );
  }

  static String _transferBody(bool credit, String? amount, String name) {
    if (amount == null) return PushStrings.t('wallet.transfer_body');
    final vars = {'amount': amount, 'name': name};
    if (name.isEmpty) {
      return PushStrings.t(
        credit ? 'wallet.received_body_amount' : 'wallet.paid_body_amount',
        vars,
      );
    }
    return PushStrings.t(
      credit ? 'wallet.received_from' : 'wallet.paid_to',
      vars,
    );
  }

  static bool _within(DateTime? last) =>
      last != null && DateTime.now().difference(last) < cooldown;

  /// RN: `Rs. 12.00`; a non-numeric value as-is; empty → null.
  static String? _money(String? raw) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    final n = num.tryParse(v);
    return n == null ? 'Rs. $v' : 'Rs. ${n.toStringAsFixed(2)}';
  }
}
