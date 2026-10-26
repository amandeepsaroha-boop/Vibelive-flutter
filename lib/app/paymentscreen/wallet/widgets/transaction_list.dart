import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../api/paymentscreen/wallet_models.dart';
import '../../../component/c_state_view.dart';
import '../../../component/c_text.dart';
import '../../../component/infinite_scroll.dart';
import '../../../component/skeleton.dart';
import '../helper/transaction_pager.dart';
import '../helper/transaction_row.dart';
import '../helper/wallet_palette.dart';
import 'transaction_tile.dart';

/// History of the selected tab: skeleton on first load, then paged rows with
/// pull-to-refresh (RN FlatList).
class TransactionList extends StatefulWidget {
  const TransactionList({
    super.key,
    required this.pager,
    required this.myName,
    required this.onRefresh,
    required this.onInvoice,
    required this.bottomPadding,
  });

  final TransactionPager pager;

  /// Settles call rows without a wallet type (RN `userData.name`).
  final String? myName;
  final Future<void> Function() onRefresh;
  final Future<void> Function(TransactionRow row) onInvoice;
  final double bottomPadding;

  @override
  State<TransactionList> createState() => _TransactionListState();
}

class _TransactionListState extends State<TransactionList> {
  List<WalletTransaction>? _source;
  String? _sourceName;
  List<TransactionRow> _rows = const [];

  /// Rows are mapped once per loaded list, not on every build.
  List<TransactionRow> _rowsOf(List<WalletTransaction> source) {
    if (!identical(source, _source) || _sourceName != widget.myName) {
      _source = source;
      _sourceName = widget.myName;
      _rows = TransactionRow.visible(source, widget.myName);
    }
    return _rows;
  }

  @override
  Widget build(BuildContext context) {
    final pager = widget.pager;
    return ValueListenableBuilder<TransactionListState>(
      valueListenable: pager,
      builder: (context, s, _) {
        final error = s.error;
        if (s.loading) return const TransactionListSkeleton();
        if (error != null && s.rows.isEmpty) {
          return CStateView.error(context, error, onRetry: pager.refresh);
        }
        final rows = _rowsOf(s.rows);
        return InfiniteScroll(
          hasMore: s.hasMore,
          loadingMore: s.loadingMore,
          loadMoreFailed: s.loadMoreFailed,
          onLoadMore: pager.loadMore,
          onRefresh: widget.onRefresh,
          // Edge to edge; only the safe-area / navbar room at the end.
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          slivers: [
            if (rows.isEmpty)
              const SliverToBoxAdapter(child: _Empty())
            else
              SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) => TransactionTile(
                  key: ValueKey(rows[i].key),
                  row: rows[i],
                  onInvoice: widget.onInvoice,
                ),
              ),
            if (rows.isNotEmpty &&
                !s.hasMore &&
                !s.loadingMore &&
                !s.loadMoreFailed)
              const SliverToBoxAdapter(child: _End()),
          ],
        );
      },
    );
  }
}

/// RN list footer once everything is loaded.
class _End extends StatelessWidget {
  const _End();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 14.ms),
    child: CText(
      'payment:wallet.no_more',
      size: 11,
      weight: FontWeight.w700,
      color: WalletPalette.of(context).subtle,
      align: TextAlign.center,
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final p = WalletPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 40.ms),
      child: Column(
        children: [
          Icon(LucideIcons.clock, size: 32.ms, color: p.subtle),
          SizedBox(height: 12.ms),
          CText(
            'payment:wallet.empty',
            weight: FontWeight.w700,
            color: p.muted,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Transaction rows in skeleton form (first load of a tab): one shimmer
/// for the whole list.
class TransactionListSkeleton extends StatelessWidget {
  const TransactionListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Shimmer(
            child: Column(
              children: [
                // Same frame as the rows: flush, one line between.
                for (var i = 0; i < 6; i++)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.ms,
                      vertical: 14.ms,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: WalletPalette.of(context).cardBorder,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        SkeletonBox(width: 44.ms, height: 44.ms, radius: 14),
                        SizedBox(width: 12.ms),
                        Expanded(
                          child: SkeletonLines(
                            lines: 3,
                            height: 10.ms,
                            gap: 6.ms,
                          ),
                        ),
                        SizedBox(width: 24.ms),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SkeletonBox(width: 64.ms, height: 16.ms, radius: 6),
                            SizedBox(height: 6.ms),
                            SkeletonBox(width: 48.ms, height: 12.ms, radius: 6),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
