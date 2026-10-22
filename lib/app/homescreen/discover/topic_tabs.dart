import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/homescreen/home_models.dart';
import '../../api/listingflow/filter_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';

/// Horizontal topic chips (RN `TabSelector`): All, Popular, topics. A newly
/// selected chip that is cut off is centred; a fully visible one never
/// moves. Skeleton chips while topics load.
class TopicTabs extends StatefulWidget {
  const TopicTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.loading = false,
  });

  final List<DiscoverTab> tabs;
  final DiscoverTab selected;
  final ValueChanged<DiscoverTab> onSelect;
  final bool loading;

  /// Same tab: the strip rebuilds topic tabs as new objects, so compare by
  /// kind and label, never by identity.
  static bool same(DiscoverTab a, DiscoverTab b) =>
      a.kind == b.kind && sameText(a.label, b.label);

  static String _id(DiscoverTab t) => '${t.kind.name}:${t.label.toLowerCase()}';

  @override
  State<TopicTabs> createState() => _TopicTabsState();
}

class _TopicTabsState extends State<TopicTabs> {
  final _scroll = ScrollController();
  final _keys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(TopicTabs old) {
    super.didUpdateWidget(old);
    if (!TopicTabs.same(old.selected, widget.selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    if (!_scroll.hasClients) return;
    if (widget.selected.isAll) {
      if (_scroll.offset > 0) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    final ctx = _keys[TopicTabs._id(widget.selected)]?.currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox) return;
    final viewport = RenderAbstractViewport.of(box);
    final start = viewport.getOffsetToReveal(box, 0).offset;
    final end = viewport.getOffsetToReveal(box, 1).offset;
    final x = _scroll.offset;
    if (x >= end && x <= start) return; // fully visible: never nudge
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chipBg = c.isDark ? AppColors.whiteA(0.04) : AppColors.white;
    final chipBorder = c.isDark ? AppColors.whiteA(0.14) : AppColors.slate200;
    final text = c.isDark ? AppColors.whiteA(0.75) : const Color(0xFF555555);

    return SizedBox(
      height: 48.ms,
      child: ListView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 15.ms, vertical: 8.ms),
        children: [
          for (final tab in widget.tabs)
            Padding(
              key: _keys.putIfAbsent(TopicTabs._id(tab), GlobalKey.new),
              padding: EdgeInsets.only(right: 8.ms),
              child: Pressable(
                activeOpacity: 0.75,
                onPressed: () => widget.onSelect(tab),
                child: _Chip(
                  tab: tab,
                  selected: TopicTabs.same(tab, widget.selected),
                  bg: chipBg,
                  border: chipBorder,
                  text: text,
                ),
              ),
            ),
          if (widget.loading)
            Shimmer(
              child: Row(
                children: [
                  for (final w in const [85, 110, 75, 95])
                    Padding(
                      padding: EdgeInsets.only(right: 8.ms),
                      child: SkeletonBox(
                        width: w.ms,
                        height: 32.ms,
                        radius: 6.ms,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.tab,
    required this.selected,
    required this.bg,
    required this.border,
    required this.text,
  });

  final DiscoverTab tab;
  final bool selected;
  final Color bg;
  final Color border;
  final Color text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onAccent : text;
    final key = tab.titleKey;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 32.ms,
      padding: EdgeInsets.symmetric(horizontal: 12.ms),
      decoration: BoxDecoration(
        color: selected ? c.accent : bg,
        borderRadius: BorderRadius.circular(6.ms),
        border: Border.all(color: selected ? c.accent : border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tab.isPopular) ...[
            Icon(LucideIcons.zap, size: 16.ms, color: fg),
            SizedBox(width: 6.ms),
          ],
          key == null
              ? CText.raw(
                  tab.label,
                  size: 11,
                  weight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                )
              : CText(
                  key,
                  size: 11,
                  weight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
        ],
      ),
    );
  }
}
