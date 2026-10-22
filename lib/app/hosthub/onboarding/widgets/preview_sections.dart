import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/host_palette.dart';

/// A titled card of the preview with its "Edit" link.
class PreviewSection extends StatelessWidget {
  const PreviewSection({
    super.key,
    required this.title,
    required this.onEdit,
    required this.child,
    this.editKey,
  });

  /// i18n key.
  final String title;
  final VoidCallback onEdit;
  final Widget child;
  final Key? editKey;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final dark = p.isDark;
    // The client profile's card look (ProfileVibeCard).
    return Container(
      margin: EdgeInsets.only(bottom: 14.ms),
      padding: EdgeInsets.fromLTRB(14.ms, 12.ms, 12.ms, 14.ms),
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.04) : AppColors.blackA(0.025),
        borderRadius: BorderRadius.circular(22.ms),
        border: Border.all(
          color: dark ? AppColors.whiteA(0.07) : AppColors.blackA(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: CText(
                  title,
                  size: 13,
                  weight: FontWeight.w700,
                  color: p.muted,
                ),
              ),
              Pressable(
                key: editKey,
                onPressed: onEdit,
                hitPadding: EdgeInsets.all(8.ms),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.pencil, size: 13.ms, color: p.accent),
                    SizedBox(width: 4.ms),
                    CText(
                      'hostflow:preview.edit',
                      size: 13,
                      weight: FontWeight.w700,
                      color: p.accent,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.ms),
          child,
        ],
      ),
    );
  }
}

/// Icon + text line (languages, location, a rate…).
class PreviewLine extends StatelessWidget {
  const PreviewLine({
    super.key,
    required this.icon,
    required this.text,
    this.trailing,
  });

  final IconData icon;

  /// Literal text (server / user data, or pre-translated).
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.ms),
      child: Row(
        children: [
          Icon(icon, size: 17.ms, color: p.text),
          SizedBox(width: 10.ms),
          Expanded(
            child: CText.raw(
              text,
              size: 14.5,
              weight: FontWeight.w500,
              color: p.text,
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: 8.ms),
            Flexible(
              child: CText.raw(
                trailing!,
                size: 14.5,
                weight: FontWeight.w700,
                color: p.text,
                align: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
