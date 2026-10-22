import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/hosthub_queries.dart';
import '../../../api/hosthub/stats_models.dart';
import '../../../component/c_text.dart';
import '../../onboarding/helper/host_palette.dart';

/// Earnings · Calls · Rating, from the persisted host stats (zeros until
/// the first read; a failed refresh keeps the last figures).
class HostQuickStats extends HookWidget {
  const HostQuickStats({super.key});

  @override
  Widget build(BuildContext context) {
    final s = useHostStats(context).data ?? HostStats.empty;
    final tiles = [
      (HostStats.formatCurrency(s.totalEarnings), 'hostflow:approved.earnings'),
      (HostStats.formatNumber(s.totalCalls), 'hostflow:approved.calls'),
      (s.averageRating.toStringAsFixed(1), 'hostflow:approved.rating'),
    ];
    return Row(
      children: [
        for (final (i, (value, label)) in tiles.indexed) ...[
          if (i > 0) SizedBox(width: 10.ms),
          Expanded(
            child: _Tile(value: value, label: label),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.ms, vertical: 14.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 26.ms,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CText.raw(
                value,
                size: 20,
                weight: FontWeight.w800,
                color: p.text,
              ),
            ),
          ),
          SizedBox(height: 4.ms),
          CText(
            label,
            size: 12,
            weight: FontWeight.w500,
            color: p.muted,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
