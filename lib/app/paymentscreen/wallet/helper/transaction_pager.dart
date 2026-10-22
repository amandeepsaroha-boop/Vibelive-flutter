import 'package:flutter/foundation.dart';

import '../../../../core/network/api_exception.dart';
import '../../../api/paymentscreen/payment_queries.dart';
import '../../../api/paymentscreen/transaction_api.dart';
import '../../../api/paymentscreen/wallet_models.dart';

/// Loads one page of a wallet tab.
typedef TransactionPageLoader =
    Future<List<WalletTransaction>> Function(
      TransactionFilter filter,
      int page, {
      required bool fresh,
    });

/// Immutable snapshot of the history list.
@immutable
class TransactionListState {
  const TransactionListState({
    this.filter = TransactionFilter.all,
    this.rows = const [],
    this.page = 0,
    this.hasMore = true,
    this.loading = true,
    this.loadingMore = false,
    this.loadMoreFailed = false,
    this.error,
  });

  final TransactionFilter filter;

  /// Every loaded row, commission rows included (they count for paging).
  final List<WalletTransaction> rows;

  /// Last loaded page (0: none yet).
  final int page;
  final bool hasMore;

  /// First page of this tab in flight with nothing to show: skeleton.
  final bool loading;
  final bool loadingMore;
  final bool loadMoreFailed;

  /// First page failed with nothing to show.
  final ApiException? error;

  TransactionListState copyWith({
    List<WalletTransaction>? rows,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    bool? loadMoreFailed,
    ApiException? error,
    bool clearError = false,
  }) => TransactionListState(
    filter: filter,
    rows: rows ?? this.rows,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Wallet history paging (RN `loadTransactions` / `handleLoadMore`): pages
/// of [pageSize]; a short page is the last one. A tab change or refresh
/// replaces the list with a fresh page 1; answers for a previous tab are
/// dropped.
class TransactionPager extends ValueNotifier<TransactionListState> {
  TransactionPager({
    TransactionPageLoader? load,
    List<WalletTransaction>? Function(TransactionFilter filter)? cached,
    this.pageSize = TransactionApi.pageSize,
  }) : _load = load ?? _defaultLoad,
       _cached = cached ?? _defaultCached,
       super(const TransactionListState());

  final TransactionPageLoader _load;
  final List<WalletTransaction>? Function(TransactionFilter filter) _cached;
  final int pageSize;

  /// Bumped by every tab change / refresh: late answers of older requests
  /// are ignored.
  int _generation = 0;
  bool _disposed = false;

  static Future<List<WalletTransaction>> _defaultLoad(
    TransactionFilter filter,
    int page, {
    required bool fresh,
  }) => fetchWalletTransactionPage(filter: filter, page: page, fresh: fresh);

  static List<WalletTransaction>? _defaultCached(TransactionFilter filter) =>
      cachedWalletTransactions(filter: filter);

  /// Shows [filter]: its cached page 1 at once (else a skeleton), then
  /// page 1 again unless the cached one is still fresh (a tab switched back
  /// to, or a page prefetched on the way here, costs no request).
  Future<void> select(TransactionFilter filter) {
    final seed = _cached(filter);
    value = TransactionListState(
      filter: filter,
      rows: seed ?? const [],
      page: seed == null ? 0 : 1,
      hasMore: seed == null || seed.length >= pageSize,
      loading: seed == null,
    );
    return _reload(fresh: false);
  }

  /// Fresh page 1 of the current tab (pull-to-refresh, after a payment).
  Future<void> refresh() => _reload(fresh: true);

  Future<void> _reload({required bool fresh}) async {
    final gen = ++_generation;
    final filter = value.filter;
    try {
      final rows = await _load(filter, 1, fresh: fresh);
      if (!_current(gen)) return;
      value = TransactionListState(
        filter: filter,
        rows: rows,
        page: 1,
        hasMore: rows.length == pageSize,
        loading: false,
      );
    } on ApiException catch (e) {
      if (!_current(gen)) return;
      // RN fails silently and keeps what it shows; with nothing shown, the
      // list offers a retry instead of an endless skeleton.
      value = value.copyWith(
        loading: false,
        loadingMore: false,
        hasMore: value.rows.isNotEmpty && value.hasMore,
        error: value.rows.isEmpty ? e : null,
        clearError: value.rows.isNotEmpty,
      );
    }
  }

  /// Next page, when the loaded rows fill every page so far (RN guard).
  Future<void> loadMore() async {
    final s = value;
    if (s.loading || s.loadingMore || !s.hasMore || s.page == 0) return;
    if (s.rows.length < s.page * pageSize) return;
    final gen = _generation;
    final next = s.page + 1;
    value = s.copyWith(loadingMore: true, loadMoreFailed: false);
    try {
      final rows = await _load(s.filter, next, fresh: false);
      if (!_current(gen)) return;
      value = value.copyWith(
        rows: [...value.rows, ...rows],
        page: next,
        hasMore: rows.length == pageSize,
        loadingMore: false,
      );
    } on ApiException {
      if (!_current(gen)) return;
      value = value.copyWith(loadingMore: false, loadMoreFailed: true);
    }
  }

  bool _current(int gen) => !_disposed && gen == _generation;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
