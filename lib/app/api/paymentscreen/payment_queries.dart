import 'package:flutter/widgets.dart';

import '../../../core/network/api_client.dart';

import '../../../core/network/strapi.dart';
import '../../../core/query/query_hooks.dart';
import '../../../core/query/query_persist.dart';
import '../../../core/session/session_store.dart';
import '../../../core/utils/log.dart';
import '../splashscreen/splash_queries.dart';
import 'bank_api.dart';
import 'billing_models.dart';
import 'checkout_models.dart';
import 'invoice_api.dart';
import 'payment_keys.dart';
import 'pricing_api.dart';
import 'razorpay_api.dart';
import 'recharge_api.dart';
import 'transaction_api.dart';
import 'wallet_api.dart';
import 'wallet_models.dart';

String? _me(String? userDocumentId) =>
    userDocumentId ?? SessionStore.instance.value.userDocumentId;

// ── Wallet balance ───────────────────────────────────────────────────────

/// Every wallet of the user (cash, earnings, header total): the one balance
/// query for the wallet screen, Discovery, Search, Explore, Favourites and
/// the profile modal. On disk for an instant first frame. Every balance
/// change (call end, payment, transfer, wallet push, Home back on top)
/// invalidates it, so a mount within a minute reuses it; the pre-call check
/// ([ensureWalletBalance]) always reads it fresh.
QueryResult<WalletBalance, ApiException> useWalletBalance(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final uid = _me(userDocumentId);
  return usePersistedQuery<WalletBalance>(
    PaymentKeys.wallet(uid),
    () => WalletApi.fetchBalance(uid!),
    context: context,
    enabled: enabled && uid != null,
    staleDuration: StaleTime.short,
    toJson: (balance) => balance.toJson(),
    fromJson: WalletBalance.fromJson,
  );
}

/// Balance outside widgets, fresh by default (pre-call balance check). Also
/// refreshes the disk copy.
Future<WalletBalance> ensureWalletBalance({
  String? userDocumentId,
  Duration staleDuration = StaleTime.none,
}) async {
  final uid = _me(userDocumentId);
  if (uid == null) throw const ApiException(ApiErrorType.unauthorized);
  final key = PaymentKeys.wallet(uid);
  return queryCache.fetchQuery<WalletBalance>(key, () async {
    final balance = await WalletApi.fetchBalance(uid);
    QueryPersist.write(key, balance.toJson());
    return balance;
  }, staleDuration: staleDuration);
}

// ── Transactions ─────────────────────────────────────────────────────────

/// First page of the "All" tab, on disk like the balance (RN app cache
/// wallet section). Same cache entry as `useWalletTransactions()` page 1.
QueryResult<List<WalletTransaction>, ApiException> useRecentTransactions(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final uid = _me(userDocumentId);
  return usePersistedQuery<List<WalletTransaction>>(
    PaymentKeys.transactionPage(
      uid,
      TransactionFilter.all,
      1,
      TransactionApi.pageSize,
    ),
    () => TransactionApi.fetchPage(uid!),
    context: context,
    enabled: enabled && uid != null,
    staleDuration: StaleTime.short,
    toJson: (rows) => [for (final tx in rows) tx.toJson()],
    fromJson: _transactionsFromJson,
  );
}

/// One page of a wallet tab. A page shorter than [pageSize] is the last.
QueryResult<List<WalletTransaction>, ApiException> useWalletTransactions(
  BuildContext context, {
  TransactionFilter filter = TransactionFilter.all,
  int page = 1,
  int pageSize = TransactionApi.pageSize,
  String? userDocumentId,
  bool enabled = true,
}) {
  final uid = _me(userDocumentId);
  return useApiQuery<List<WalletTransaction>>(
    PaymentKeys.transactionPage(uid, filter, page, pageSize),
    () => TransactionApi.fetchPage(
      uid!,
      filter: filter,
      page: page,
      size: pageSize,
    ),
    context: context,
    enabled: enabled && uid != null,
    staleDuration: StaleTime.short,
  );
}

/// Load-more pages and PayU status polling (pass `StaleTime.none`).
Future<List<WalletTransaction>> ensureWalletTransactions({
  TransactionFilter filter = TransactionFilter.all,
  int page = 1,
  int pageSize = TransactionApi.pageSize,
  String? userDocumentId,
  Duration staleDuration = StaleTime.short,
}) async {
  final uid = _me(userDocumentId);
  if (uid == null) throw const ApiException(ApiErrorType.unauthorized);
  return queryCache.fetchQuery<List<WalletTransaction>>(
    PaymentKeys.transactionPage(uid, filter, page, pageSize),
    () => TransactionApi.fetchPage(
      uid,
      filter: filter,
      page: page,
      size: pageSize,
    ),
    staleDuration: staleDuration,
  );
}

/// Pull-to-refresh, or after a checkout closes: refetch balance and history.
void invalidateWalletQueries() =>
    queryCache.invalidateAll(PaymentKeys.walletData);

/// Page 1 of [filter] already in memory, else (for "All") the disk copy:
/// the wallet screen's instant first frame (RN app cache). Null when none.
List<WalletTransaction>? cachedWalletTransactions({
  TransactionFilter filter = TransactionFilter.all,
  String? userDocumentId,
}) {
  final uid = _me(userDocumentId);
  if (uid == null) return null;
  final key = _firstPageKey(uid, filter);
  final memory = queryCache.getQueryData<List<WalletTransaction>, ApiException>(
    key,
  );
  if (memory != null || filter != TransactionFilter.all) return memory;
  return QueryPersist.read<List<WalletTransaction>>(key, _transactionsFromJson);
}

/// One page for the wallet screen's pager ([fresh]: pull-to-refresh, tab
/// change). Page 1 of "All" also refreshes its disk copy.
Future<List<WalletTransaction>> fetchWalletTransactionPage({
  TransactionFilter filter = TransactionFilter.all,
  int page = 1,
  bool fresh = false,
  String? userDocumentId,
}) async {
  final uid = _me(userDocumentId);
  final rows = await ensureWalletTransactions(
    filter: filter,
    page: page,
    userDocumentId: uid,
    staleDuration: fresh ? StaleTime.none : StaleTime.short,
  );
  if (uid != null && filter == TransactionFilter.all && page == 1) {
    QueryPersist.write(_firstPageKey(uid, filter), [
      for (final tx in rows) tx.toJson(),
    ]);
  }
  return rows;
}

/// Warms the wallet screen's first page ("All") on the way there.
void prefetchWalletTransactions() =>
    fetchWalletTransactionPage().then((_) {}, onError: (Object _) {});

RawQueryKey _firstPageKey(String uid, TransactionFilter filter) =>
    PaymentKeys.transactionPage(uid, filter, 1, TransactionApi.pageSize);

List<WalletTransaction> _transactionsFromJson(Object? json) => [
  for (final tx in json! as List) WalletTransaction.fromJson(tx),
];

// ── Configuration ────────────────────────────────────────────────────────

/// GST on earnings → cash transfers. While loading or on error, use
/// [GstConfig.defaultIgstRate] (RN behaviour).
QueryResult<GstConfig, ApiException> useGstConfig(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<GstConfig>(
  PaymentKeys.gst,
  PricingApi.fetchGstConfig,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.long,
);

Future<GstConfig> ensureGstConfig() => queryCache.fetchQuery<GstConfig>(
  PaymentKeys.gst,
  PricingApi.fetchGstConfig,
  staleDuration: StaleTime.long,
);

/// Pricing limits, commissions and fees (also used by hosthub).
QueryResult<PricingConfig, ApiException> usePricingConfig(
  BuildContext context, {
  bool enabled = true,
}) => useApiQuery<PricingConfig>(
  PaymentKeys.pricingConfig,
  PricingApi.fetchPricingConfig,
  context: context,
  enabled: enabled,
  staleDuration: StaleTime.long,
);

Future<PricingConfig> ensurePricingConfig() =>
    queryCache.fetchQuery<PricingConfig>(
      PaymentKeys.pricingConfig,
      PricingApi.fetchPricingConfig,
      staleDuration: StaleTime.long,
    );

// ── Bank details ─────────────────────────────────────────────────────────

/// Saved payout account; data is null when none exists yet.
QueryResult<BankDetail?, ApiException> useBankDetail(
  BuildContext context, {
  String? userDocumentId,
  bool enabled = true,
}) {
  final uid = _me(userDocumentId);
  return useApiQuery<BankDetail?>(
    PaymentKeys.bankDetail(uid),
    () => BankApi.fetchBankDetail(uid!),
    context: context,
    enabled: enabled && uid != null,
    staleDuration: StaleTime.short,
  );
}

MutationResult<BankDetail, ApiException, BankDetailInput> useSaveBankDetail({
  void Function(BankDetail saved)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<BankDetail, BankDetailInput>(
  BankApi.save,
  invalidates: const [PaymentKeys.bankDetails],
  onSuccess: (saved, _) => onSuccess?.call(saved),
  onError: (e, _) => onError?.call(e),
);

// ── Top-up ───────────────────────────────────────────────────────────────

/// Creates the order on the gateway the backend selected and returns what
/// the checkout needs ([PayUCheckout] or [RazorpayCheckout]).
MutationResult<RechargeCheckout, ApiException, RechargeRequest>
useStartWalletRecharge({
  void Function(RechargeCheckout checkout)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<RechargeCheckout, RechargeRequest>(
  startWalletRecharge,
  invalidates: PaymentKeys.walletData,
  onSuccess: (checkout, _) => onSuccess?.call(checkout),
  onError: (e, _) => onError?.call(e),
);

/// Verifies the Razorpay SDK result (with status recovery). Check
/// [RazorpayVerification.outcome]: pending must not be shown as a failure.
MutationResult<RazorpayVerification, ApiException, RazorpayPayment>
useVerifyRazorpayPayment({
  void Function(RazorpayVerification result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<RazorpayVerification, RazorpayPayment>(
  RazorpayApi.verifyWithFallback,
  invalidates: PaymentKeys.walletData,
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);

/// Fire-and-forget success callback to the gateway's backend route.
MutationResult<void, ApiException, RechargeReport> useReportRechargeSuccess() =>
    useApiMutation<void, RechargeReport>(
      RechargeApi.reportSuccess,
      invalidates: PaymentKeys.walletData,
    );

/// Fire-and-forget failure callback to the gateway's backend route.
MutationResult<void, ApiException, RechargeReport> useReportRechargeFailure() =>
    useApiMutation<void, RechargeReport>(
      RechargeApi.reportFailure,
      invalidates: PaymentKeys.walletData,
    );

/// [useStartWalletRecharge] outside widgets (the wallet checkout flow).
Future<RechargeCheckout> startWalletRecharge(RechargeRequest request) =>
    ApiClient.guard(
      () async => RechargeApi.startWalletRecharge(
        request.appConfig != null
            ? request
            : request.withAppConfig(await _appConfigOrNull()),
      ),
    );

/// [useVerifyRazorpayPayment] outside widgets. Pending must not be shown as
/// a failure.
Future<RazorpayVerification> verifyRazorpayPayment(RazorpayPayment payment) =>
    ApiClient.guard(() => RazorpayApi.verifyWithFallback(payment));

/// Best effort, never throws (RN `reportPaymentSuccess`).
Future<void> reportRechargeSuccess(RechargeReport report) =>
    RechargeApi.reportSuccess(report);

/// Best effort, never throws (RN `reportPaymentFailure`).
Future<void> reportRechargeFailure(RechargeReport report) =>
    RechargeApi.reportFailure(report);

/// Best effort, never throws (RN `reportCheckoutAbandoned`).
Future<void> reportCheckoutAbandoned({
  required String transactionId,
  required String classification,
  int? errorCode,
  String? description,
}) => RazorpayApi.reportCheckoutAbandoned(
  transactionId: transactionId,
  classification: classification,
  errorCode: errorCode,
  description: description,
);

/// RN ignored app-config failures here: the initiate response, or the
/// build-time key, usually carries the Razorpay key id anyway.
Future<JsonMap?> _appConfigOrNull() async {
  try {
    return (await ensureAppConfig()).raw;
  } on ApiException catch (e) {
    Log.w('payment', 'app-config unavailable for the Razorpay key: $e');
    return null;
  }
}

// ── Transfer ─────────────────────────────────────────────────────────────

/// Earnings → cash. Validate with [EarningsTransfer] first.
MutationResult<JsonMap, ApiException, double> useTransferEarningsToCash({
  void Function(JsonMap result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<JsonMap, double>(
  WalletApi.transferEarningsToCash,
  invalidates: PaymentKeys.walletData,
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);

// ── Invoices ─────────────────────────────────────────────────────────────

/// Resolves a transaction's invoice PDF. Open [InvoicePdfLookup.url] when
/// ready, else show the status's title/message keys.
MutationResult<InvoicePdfLookup, ApiException, WalletTransaction>
useInvoicePdf({
  void Function(InvoicePdfLookup lookup)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<InvoicePdfLookup, WalletTransaction>(
  InvoiceApi.resolvePdf,
  onSuccess: (lookup, _) => onSuccess?.call(lookup),
  onError: (e, _) => onError?.call(e),
);

/// Rebuilds an invoice PDF; the history shows it once ready.
MutationResult<JsonMap, ApiException, Object> useGenerateInvoicePdf({
  void Function(JsonMap result)? onSuccess,
  void Function(ApiException error)? onError,
}) => useApiMutation<JsonMap, Object>(
  InvoiceApi.generatePdf,
  invalidates: const [PaymentKeys.transactions],
  onSuccess: (result, _) => onSuccess?.call(result),
  onError: (e, _) => onError?.call(e),
);
