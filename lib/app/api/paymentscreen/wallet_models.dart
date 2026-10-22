import 'dart:math' as math;

import '../../../core/network/strapi.dart';
import 'payment_json.dart';

/// `wallet_type` values used by the backend.
abstract final class WalletType {
  static const cash = 'CASH_WALLET';
  static const earnings = 'EARNINGS_WALLET';
}

/// One `/wallets` row. [raw] keeps every field.
class Wallet {
  const Wallet(this.raw);

  final JsonMap raw;

  factory Wallet.fromJson(Object? json) =>
      Wallet(Map<String, dynamic>.from(json! as Map));

  JsonMap toJson() => raw;

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// Upper-cased `wallet_type` (`CASH_WALLET`, `EARNINGS_WALLET`), or ''.
  String get type => (J.str(raw['wallet_type']) ?? '').toUpperCase();

  /// RN matches by substring, not the exact enum value.
  bool get isCash => type.contains('CASH');
  bool get isEarnings => type.contains('EARNING');

  /// Null when the backend sent no usable number.
  double? get balance => J.number(raw['balance']);

  JsonMap? get user => Strapi.map(raw['user']);

  /// Wallet used for transfer notifications (RN `pickPreferredWallet`): the
  /// cash wallet, else the first one, else the legacy one-to-one `wallet`.
  static Wallet? preferredOf(JsonMap? publicUser) {
    final wallets = [
      for (final row in Strapi.list(publicUser?['wallets'])) Wallet(row),
    ];
    if (wallets.isNotEmpty) {
      return wallets.firstWhere(
        (w) => w.type == WalletType.cash,
        orElse: () => wallets.first,
      );
    }
    final legacy = Strapi.map(publicUser?['wallet']);
    return legacy == null ? null : Wallet(legacy);
  }
}

/// Every wallet row of a user (`/wallets?filters[user]…`), shared by the
/// wallet screen and the balance chips on Discovery, Search, Explore,
/// Favourites and the profile modal.
class WalletBalance {
  const WalletBalance(this.wallets);

  final List<Wallet> wallets;

  factory WalletBalance.fromResponse(dynamic body) =>
      WalletBalance([for (final row in paymentRows(body)) Wallet(row)]);

  factory WalletBalance.fromJson(Object? json) {
    final map = json! as Map;
    return WalletBalance([
      for (final w in map['wallets'] as List) Wallet.fromJson(w),
    ]);
  }

  JsonMap toJson() => {
    'wallets': [for (final w in wallets) w.toJson()],
  };

  bool get hasWallet => wallets.isNotEmpty;

  /// First row (RN `fetchWallets().data`).
  Wallet? get primary => wallets.firstOrNull;

  Wallet? get cashWallet => wallets.where((w) => w.isCash).firstOrNull;
  Wallet? get earningsWallet => wallets.where((w) => w.isEarnings).firstOrNull;

  /// Never negative. Without a cash row, legacy single-wallet users read the
  /// primary wallet; an earnings row is never counted as cash.
  double get cashBalance {
    final cash = cashWallet;
    final legacy = primary;
    final value = cash != null
        ? _firstNumber(cash.raw, const [
            'balance',
            'cash_balance',
            'cashBalance',
          ])
        : legacy != null && !legacy.isEarnings
        ? _firstNumber(legacy.raw, const ['cashBalance', 'balance'])
        : null;
    return math.max(0, value ?? 0);
  }

  /// Never negative.
  double get earningsBalance {
    final earnings = earningsWallet;
    final value = earnings != null
        ? _firstNumber(earnings.raw, const [
            'balance',
            'earnings_wallet_balance',
            'earningsBalance',
          ])
        : _firstNumber(primary?.raw, const ['earningsBalance']);
    return math.max(0, value ?? 0);
  }

  /// Header figure (RN Discovery/Search/Explore/Favourites): the sum of every
  /// row's balance. Equals cash + earnings for the usual two wallets.
  double get totalBalance =>
      wallets.fold(0, (sum, w) => sum + (w.balance ?? 0));

  static double? _firstNumber(JsonMap? raw, List<String> keys) {
    if (raw == null) return null;
    for (final key in keys) {
      final v = J.number(raw[key]);
      if (v != null && v.isFinite) return v;
    }
    return null;
  }
}

/// Wallet screen tabs (RN `activeTab`).
enum TransactionFilter { all, cash, earnings }

enum TransactionDirection { credit, debit }

/// Row title on the wallet screen.
enum TransactionKind { walletTransfer, topup, received, paid }

enum CallKind { audio, video, other }

/// One `/transactions` row. [raw] keeps every field; the getters port the
/// RN wallet screen's reading of it.
class WalletTransaction {
  const WalletTransaction(this.raw);

  final JsonMap raw;

  factory WalletTransaction.fromJson(Object? json) =>
      WalletTransaction(Map<String, dynamic>.from(json! as Map));

  JsonMap toJson() => raw;

  int? get id => J.integer(raw['id']);
  String? get documentId => J.str(raw['documentId']);

  /// `transaction_Id`: gateway or backend reference (`RZP_…`, `pay_…`,
  /// `…-COMM`).
  String? get reference => J.str(raw['transaction_Id']);

  /// Null when the backend sent no usable number.
  double? get amount => J.number(raw['amount']);

  /// `success`, `failure`, anything else is pending.
  String? get paymentStatus => J.str(raw['paymentStatus']);
  bool get isSuccess => paymentStatus == 'success';
  bool get isFailure => paymentStatus == 'failure';

  /// Lower-cased `transactionType`.
  String get type => (J.str(raw['transactionType']) ?? '').toLowerCase();
  String? get method => J.str(raw['method']);
  DateTime? get createdAt => J.date(raw['createdAt']);

  Wallet? get fromWallet => _wallet(raw['FromWallet']);
  Wallet? get toWallet => _wallet(raw['to_wallet']);

  JsonMap? get call => Strapi.map(raw['call']);
  CallKind get callKind => switch ((J.str(call?['type']) ?? '').toLowerCase()) {
    'voicecall' => CallKind.audio,
    'videocall' => CallKind.video,
    _ => CallKind.other,
  };
  String? get callerName => J.str(Strapi.map(call?['caller'])?['name']);
  String? get receiverName => J.str(Strapi.map(call?['receiver'])?['name']);

  JsonMap? get metadata {
    final m = raw['metadata'];
    return m is Map ? Map<String, dynamic>.from(m) : null;
  }

  /// Populated invoices (`invoices`, or a single legacy `invoice`).
  List<JsonMap> get invoices {
    final list = Strapi.list(raw['invoices']);
    if (list.isNotEmpty) return list;
    final single = Strapi.map(raw['invoice']);
    return single == null ? const [] : [single];
  }

  /// Platform commission rows; the wallet screen hides them.
  bool get isCommission => (reference ?? '').endsWith('-COMM');

  bool get isGatewayTopup {
    final m = (method ?? '').toLowerCase();
    final ref = reference ?? '';
    return m.contains('razorpay') ||
        ref.startsWith('RZP_') ||
        ref.startsWith('pay_') ||
        m == 'payu';
  }

  bool get isEarningsToCash =>
      fromWallet?.type == WalletType.earnings &&
      toWallet?.type == WalletType.cash;

  /// RN rule, in order. [currentUserName] only settles call rows that carry
  /// no wallet type.
  TransactionDirection directionFor(String? currentUserName) {
    if (isGatewayTopup || isEarningsToCash) return TransactionDirection.credit;
    if (type.contains('credit') ||
        type.contains('topup') ||
        type.contains('refund')) {
      return TransactionDirection.credit;
    }
    // Money leaving the cash wallet is a caller paying for a call.
    if (fromWallet?.type == WalletType.cash) return TransactionDirection.debit;
    // Money entering the earnings wallet is an expert being paid.
    if (toWallet?.type == WalletType.earnings) {
      return TransactionDirection.credit;
    }
    final me = currentUserName ?? '';
    if (me.isNotEmpty && (receiverName ?? '') == me) {
      return TransactionDirection.credit;
    }
    return TransactionDirection.debit;
  }

  bool isCreditFor(String? currentUserName) =>
      directionFor(currentUserName) == TransactionDirection.credit;

  bool isTopupFor(String? currentUserName) =>
      isGatewayTopup ||
      isEarningsToCash ||
      type.contains('topup') ||
      (isCreditFor(currentUserName) &&
          (callerName ?? '').isEmpty &&
          !isCommission &&
          !type.contains('call') &&
          toWallet?.type != WalletType.earnings);

  TransactionKind kindFor(String? currentUserName) {
    if (isEarningsToCash) return TransactionKind.walletTransfer;
    if (isTopupFor(currentUserName)) return TransactionKind.topup;
    return isCreditFor(currentUserName)
        ? TransactionKind.received
        : TransactionKind.paid;
  }

  /// The other side of a call row (caller when credited, receiver when
  /// debited). Null when unknown.
  String? counterpartyFor(String? currentUserName) =>
      isCreditFor(currentUserName) ? callerName : receiverName;

  /// Amount to show: call rows with metadata show what this side actually
  /// got (`receiverAmount`) or paid (`amountWithGST`). Null when unknown.
  double? displayAmountFor(String? currentUserName) {
    final meta = metadata;
    if (meta != null && !isCommission && raw['call'] != null) {
      final v = J.number(
        meta[isCreditFor(currentUserName) ? 'receiverAmount' : 'amountWithGST'],
      );
      if (v != null && v.isFinite) return v;
    }
    return amount;
  }

  /// PayU polling (RN): the row whose reference is, or contains, [reference].
  static WalletTransaction? findByReference(
    Iterable<WalletTransaction> rows,
    String reference,
  ) => reference.isEmpty
      ? null
      : rows.where((t) => (t.reference ?? '').contains(reference)).firstOrNull;

  static Wallet? _wallet(dynamic node) {
    final map = Strapi.map(node);
    return map == null ? null : Wallet(map);
  }
}

/// A just-made wallet transfer, for the "money received / paid" local
/// notification when the push payload doesn't say which.
class RecentWalletTransfer {
  const RecentWalletTransfer({
    required this.direction,
    required this.transaction,
    this.counterpartyName,
  });

  final TransactionDirection direction;
  final WalletTransaction transaction;

  /// Name (or username) of the other user; null when unknown.
  final String? counterpartyName;

  double? get amount => transaction.amount;

  /// Only transfers younger than this count (RN `TRANSFER_LOOKBACK_MS`).
  static const lookback = Duration(seconds: 30);

  /// RN `resolveRecentTransferForWalletNotification`: the newest recent
  /// `transfer` row touching [wallet].
  static RecentWalletTransfer? resolve(
    Iterable<WalletTransaction> rows,
    Wallet wallet, {
    required DateTime now,
  }) {
    bool same(Wallet? other) =>
        other != null &&
        ((wallet.id != null && other.id == wallet.id) ||
            (wallet.documentId != null &&
                other.documentId == wallet.documentId));

    for (final tx in rows) {
      if (tx.type != 'transfer') continue;
      final created = tx.createdAt;
      if (created == null || now.difference(created) > lookback) continue;

      final from = tx.fromWallet;
      final to = tx.toWallet;
      final isCredit = same(to);
      if (!isCredit && !same(from)) continue;

      final other = (isCredit ? from : to)?.user;
      return RecentWalletTransfer(
        direction: isCredit
            ? TransactionDirection.credit
            : TransactionDirection.debit,
        transaction: tx,
        counterpartyName: J.str(other?['name']) ?? J.str(other?['username']),
      );
    }
    return null;
  }
}
