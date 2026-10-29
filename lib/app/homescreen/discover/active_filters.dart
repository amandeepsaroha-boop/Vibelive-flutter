import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/filter_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// Removable chips for the active language / topic filters.
class ActiveFilters extends StatelessWidget {
  const ActiveFilters({
    super.key,
    required this.filter,
    required this.onChanged,
    this.source = 'discover',
  });

  final HostFilter filter;
  final ValueChanged<HostFilter> onChanged;

  /// Which screen shows the chips (analytics).
  final String source;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.ms, 0, 12.ms, 4.ms),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 6.ms,
          runSpacing: 6.ms,
          children: [
            for (final lang in filter.languages)
              _Chip(
                label: '🌐 $lang',
                onRemove: () {
                  DiscoverEvents.filterChipRemoved(
                    source: source,
                    kind: 'language',
                    value: lang,
                  );
                  onChanged(
                    HostFilter(
                      languages: [...filter.languages]..remove(lang),
                      topic: filter.topic,
                    ),
                  );
                },
              ),
            if (filter.hasTopic)
              _Chip(
                label: '🏷️ ${filter.topic}',
                onRemove: () {
                  DiscoverEvents.filterChipRemoved(
                    source: source,
                    kind: 'topic',
                    value: filter.topic,
                  );
                  onChanged(HostFilter(languages: filter.languages));
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onRemove,
      child: Container(
        padding: EdgeInsets.fromLTRB(10.ms, 5.ms, 7.ms, 5.ms),
        decoration: BoxDecoration(
          color: c.accentA(0.12),
          borderRadius: BorderRadius.circular(20.ms),
          border: Border.all(color: c.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A long topic / category name ellipsizes inside the Wrap.
            Flexible(
              child: CText.raw(
                label,
                size: 11.5,
                weight: FontWeight.w800,
                color: c.accent,
                maxLines: 1,
              ),
            ),
            SizedBox(width: 6.ms),
            Container(
              width: 16.ms,
              height: 16.ms,
              decoration: BoxDecoration(
                color: c.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.x, size: 10.ms, color: c.onAccent),
            ),
          ],
        ),
      ),
    );
  }
}
