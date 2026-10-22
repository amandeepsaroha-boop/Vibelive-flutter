import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import 'c_loader.dart';
import 'c_text.dart';
import 'pressable.dart';

/// Every paged list in the app: pull-to-refresh, "load more" near the end,
/// and a footer (loading rows / retry / end of list). The content is [slivers],
/// so rows stay lazy (`SliverList.builder`, `SliverGrid`…).
///
/// Load-more is driven by scroll notifications, never by rebuilds: scrolling
/// itself rebuilds nothing.
class InfiniteScroll extends StatefulWidget {
  const InfiniteScroll({
    super.key,
    required this.slivers,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    this.onRefresh,
    this.loadMoreFailed = false,
    this.endLabel,
    this.controller,
    this.padding = EdgeInsets.zero,
    this.onScroll,
    this.threshold = 220,
    this.loadingBuilder,
  });

  final List<Widget> slivers;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final Future<void> Function()? onRefresh;

  /// The last next-page request failed: footer shows Retry.
  final bool loadMoreFailed;

  /// i18n key shown once everything is loaded (null = nothing).
  final String? endLabel;
  final ScrollController? controller;
  final EdgeInsets padding;

  /// Every scroll update (e.g. the navbar collapse tracker).
  final void Function(ScrollMetrics metrics)? onScroll;

  /// Unscaled distance from the end that triggers the next page.
  final double threshold;

  /// Footer while the next page loads: one or two skeleton rows shaped like
  /// the list's own (bring their `Shimmer`). They get the list's horizontal
  /// [padding]. Null: a small spinner.
  final WidgetBuilder? loadingBuilder;

  /// After a failed page, scrolling near the end retries on its own once
  /// this long has passed (RN); the footer's Retry works at any time.
  static const retryAfter = Duration(seconds: 5);

  @override
  State<InfiniteScroll> createState() => _InfiniteScrollState();
}

class _InfiniteScrollState extends State<InfiniteScroll> {
  DateTime? _failedAt;

  /// [InfiniteScroll.onLoadMore] was called this frame: [loadingMore] only
  /// turns true on the rebuild, and every scroll event until then would
  /// call it again.
  bool _asked = false;

  Widget _loadingFooter(BuildContext context, EdgeInsets padding) {
    final builder = widget.loadingBuilder;
    if (builder == null) {
      return Padding(
        padding: EdgeInsets.all(12.ms),
        child: const CLoader(size: 22),
      );
    }
    return Padding(
      padding: EdgeInsets.only(left: padding.left, right: padding.right),
      child: builder(context),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.loadMoreFailed) _failedAt = clock.now();
  }

  @override
  void didUpdateWidget(InfiniteScroll old) {
    super.didUpdateWidget(old);
    if (widget.loadMoreFailed && !old.loadMoreFailed) _failedAt = clock.now();
  }

  bool get _blocked {
    if (!widget.loadMoreFailed) return false;
    final at = _failedAt;
    return at != null && clock.now().difference(at) < InfiniteScroll.retryAfter;
  }

  bool _onNotification(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollUpdateNotification) widget.onScroll?.call(n.metrics);
    if (widget.hasMore &&
        !widget.loadingMore &&
        !_blocked &&
        n.metrics.extentAfter < moderateScale(widget.threshold)) {
      _failedAt = null;
      if (_asked) return false;
      _asked = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _asked = false);
      widget.onLoadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final loadMoreFailed = widget.loadMoreFailed;
    final loadingMore = widget.loadingMore;
    final hasMore = widget.hasMore;
    final endLabel = widget.endLabel;
    final padding = widget.padding;
    final onRefresh = widget.onRefresh;
    final footer = loadMoreFailed
        ? Center(
            child: Pressable(
              onPressed: widget.onLoadMore,
              child: Padding(
                padding: EdgeInsets.all(12.ms),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.refreshCcw, size: 14.ms, color: c.accent),
                    SizedBox(width: 6.ms),
                    CText(
                      'actions.retry',
                      size: 12,
                      weight: FontWeight.w800,
                      color: c.accent,
                    ),
                  ],
                ),
              ),
            ),
          )
        : loadingMore
        ? _loadingFooter(context, padding)
        : !hasMore && endLabel != null
        ? Padding(
            padding: EdgeInsets.all(12.ms),
            child: CText(
              endLabel,
              size: 11,
              weight: FontWeight.w700,
              color: c.textMuted,
              align: TextAlign.center,
            ),
          )
        : const SizedBox.shrink();

    final view = CustomScrollView(
      controller: widget.controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: padding.copyWith(bottom: 0),
          sliver: SliverMainAxisGroup(slivers: widget.slivers),
        ),
        SliverToBoxAdapter(child: footer),
        SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
      ],
    );

    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: onRefresh == null
          ? view
          : RefreshIndicator(
              color: c.accent,
              backgroundColor: c.modalCard,
              onRefresh: onRefresh,
              child: view,
            ),
    );
  }
}
