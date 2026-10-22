import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/resource_palette.dart';

/// RN profile sub-screen header (Categories, GST Details, Favourites):
/// 42 pt rounded back button, centered title, optional right action.
class SubPageHeader extends StatelessWidget {
  const SubPageHeader({super.key, required this.title, this.trailing});

  /// i18n key.
  final String title;

  /// Right side (42 wide); empty space keeps the title centered.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 6.ms),
      child: SizedBox(
        height: 42.ms,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SubPageButton(
                icon: LucideIcons.chevronLeft,
                iconSize: 20,
                label: 'actions.back',
                onPressed: () => context.pop(),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 52.ms),
              child: CText(
                title,
                size: 18,
                weight: FontWeight.w900,
                color: p.text,
                maxLines: 1,
              ),
            ),
            if (trailing != null)
              Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ),
      ),
    );
  }
}

/// A 42 pt rounded-square header button.
class SubPageButton extends StatelessWidget {
  const SubPageButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconSize = 16,
    this.color,
    this.busy = false,
  });

  final IconData icon;

  /// i18n key for screen readers.
  final String label;
  final VoidCallback? onPressed;
  final double iconSize;
  final Color? color;

  /// Dimmed and disabled while its action runs.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    return Pressable(
      onPressed: busy ? null : onPressed,
      semanticLabel: context.t(label),
      child: Opacity(
        opacity: busy ? 0.6 : 1,
        child: Container(
          width: 42.ms,
          height: 42.ms,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.soft,
            borderRadius: BorderRadius.circular(14.ms),
            border: Border.all(color: p.border),
          ),
          child: Icon(icon, size: iconSize.ms, color: color ?? p.text),
        ),
      ),
    );
  }
}
