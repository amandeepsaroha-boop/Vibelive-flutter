import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../onboarding/helper/host_palette.dart';

typedef HostMenuEntry = ({IconData icon, String label, VoidCallback onTap});

/// My Schedule / Call Rates / Analytics / Profile / Settings rows.
class HostMenuCard extends StatelessWidget {
  const HostMenuCard({super.key, required this.entries});
  final List<HostMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 52.ms,
                endIndent: 16.ms,
                color: p.cardBorder,
              ),
            Pressable(
              onPressed: e.onTap,
              child: SizedBox(
                height: 54.ms,
                child: Row(
                  children: [
                    SizedBox(width: 16.ms),
                    Icon(e.icon, size: 20.ms, color: p.text),
                    SizedBox(width: 16.ms),
                    Expanded(
                      child: CText(
                        e.label,
                        size: 15,
                        weight: FontWeight.w500,
                        color: p.text,
                        maxLines: 1,
                      ),
                    ),
                    Icon(LucideIcons.chevronRight, size: 18.ms, color: p.muted),
                    SizedBox(width: 14.ms),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
