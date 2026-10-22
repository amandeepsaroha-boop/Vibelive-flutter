import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';

/// "Based on your interests": ideas with a "Use" button each, and "Try
/// another suggestion".
class HostSuggestionCard extends StatelessWidget {
  const HostSuggestionCard({
    super.key,
    required this.suggestions,
    required this.onUse,
    required this.onAnother,
  });

  final List<String> suggestions;
  final ValueChanged<String> onUse;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(12.ms, 14.ms, 12.ms, 6.ms),
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(16.ms),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 4.ms, bottom: 10.ms),
            child: Row(
              children: [
                Icon(LucideIcons.sparkles, size: 18.ms, color: p.accent),
                SizedBox(width: 8.ms),
                Expanded(
                  child: CText(
                    'hostflow:suggest.header',
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: p.accent,
                  ),
                ),
              ],
            ),
          ),
          for (final s in suggestions)
            Container(
              margin: EdgeInsets.only(bottom: 8.ms),
              padding: EdgeInsets.fromLTRB(12.ms, 10.ms, 10.ms, 10.ms),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(12.ms),
                border: Border.all(color: p.cardBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CText.raw(
                      s,
                      size: 13.5,
                      height: 18.5,
                      weight: FontWeight.w500,
                      color: p.text,
                    ),
                  ),
                  SizedBox(width: 10.ms),
                  Pressable(
                    onPressed: () => onUse(s),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.ms,
                        vertical: 7.ms,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.ms),
                        border: Border.all(color: p.tintBorder, width: 1.2),
                      ),
                      child: CText(
                        'hostflow:suggest.use',
                        size: 13.5,
                        weight: FontWeight.w700,
                        color: p.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // "Try another suggestion" is hidden (product ask).
        ],
      ),
    );
  }
}
