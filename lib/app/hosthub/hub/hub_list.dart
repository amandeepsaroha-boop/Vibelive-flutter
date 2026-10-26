import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../onboarding/helper/host_palette.dart';

/// The Host Hub list look, shared by every ME → Settings list so they can't
/// drift apart: one flat card, rows split by inset dividers, no shadows.
class HubListCard extends StatelessWidget {
  const HubListCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 58.ms,
                color: p.cardBorder,
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// One row: 32 px tinted tile with an accent icon, the label (and an
/// optional subtitle), a trailing value hugging the chevron.
class HubListRow extends StatelessWidget {
  const HubListRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.leading,
    this.dimmed = false,
  });

  final IconData icon;

  /// i18n keys.
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  /// A status / value before the chevron ([status], [value]).
  final Widget? trailing;

  /// Replaces the icon inside the tile (animated icons).
  final Widget? leading;

  /// Half opacity, still tappable (it explains why).
  final bool dimmed;

  /// A translated status ("In review") in [color].
  static Widget status(String key, Color color) => CText(
    key,
    align: TextAlign.right,
    size: 12.5,
    weight: FontWeight.w700,
    color: color,
    maxLines: 1,
  );

  /// A literal value ("₹25 · ₹35") in [color].
  static Widget value(String text, Color color) => CText.raw(
    text,
    align: TextAlign.right,
    size: 12.5,
    weight: FontWeight.w700,
    color: color,
    maxLines: 1,
  );

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final row = Pressable(
      onPressed: onTap,
      child: SizedBox(
        height: (subtitle == null ? 60 : 66).ms,
        child: Row(
          children: [
            SizedBox(width: 14.ms),
            Container(
              width: 32.ms,
              height: 32.ms,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.tint,
                borderRadius: BorderRadius.circular(10.ms),
              ),
              child: leading ?? Icon(icon, size: 17.ms, color: p.accent),
            ),
            SizedBox(width: 12.ms),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CText(
                    label,
                    size: 15,
                    weight: FontWeight.w600,
                    color: p.text,
                    maxLines: 1,
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2.ms),
                    CText(
                      subtitle!,
                      size: 12.5,
                      weight: FontWeight.w500,
                      color: p.muted,
                      maxLines: 1,
                    ),
                  ],
                ],
              ),
            ),
            // The value hugs the chevron (the label keeps the free space;
            // long values ellipsize).
            if (trailing != null) ...[
              SizedBox(width: 8.ms),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 150.ms),
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1,
                  child: trailing,
                ),
              ),
            ],
            SizedBox(width: 6.ms),
            Icon(LucideIcons.chevronRight, size: 18.ms, color: p.muted),
            SizedBox(width: 12.ms),
          ],
        ),
      ),
    );
    // Only a dimmed row pays for an opacity layer.
    return dimmed ? Opacity(opacity: 0.5, child: row) : row;
  }
}
