import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/me_palette.dart';

class MeSegment<T> {
  const MeSegment(this.value, this.icon, this.label);

  final T value;
  final IconData icon;

  /// i18n key.
  final String label;
}

/// The ME pill switch (availability modes, Dashboard | Settings): the
/// active segment is a solid pill that slides to the selection.
class MeSegmented<T> extends StatelessWidget {
  const MeSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final List<MeSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final n = segments.length;
    final index = segments.indexWhere((s) => s.value == selected);
    final radius = BorderRadius.circular(12.ms);
    return Container(
      height: 38.ms + 8,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.pillBg,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Stack(
        children: [
          if (index >= 0)
            AnimatedAlign(
              alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.activeBg,
                    borderRadius: radius,
                  ),
                ),
              ),
            ),
          // Fills the pill so each label centres vertically too.
          Positioned.fill(
            child: Row(
              children: [
                for (final s in segments)
                  Expanded(
                    child: _Segment(
                      segment: s,
                      active: s.value == selected,
                      onTap: enabled ? () => onSelect(s.value) : null,
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

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.active,
    required this.onTap,
  });

  final MeSegment<T> segment;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    final fg = active ? p.activeFg : p.muted;
    return Pressable(
      activeOpacity: 0.85,
      onPressed: onTap,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(segment.icon, size: 15.ms, color: fg),
            SizedBox(width: 6.ms),
            Flexible(
              child: CText(
                segment.label,
                size: 12,
                weight: active ? FontWeight.w800 : FontWeight.w700,
                color: fg,
                maxLines: 1,
                // Tight line box: no extra leading pushing the label up.
                style: const TextStyle(height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
