import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../helper/host_palette.dart';

/// "Search topics…" box.
class HostSearchBox extends StatelessWidget {
  const HostSearchBox({
    super.key,
    required this.controller,
    required this.hint,
    this.fieldKey,
  });

  final TextEditingController controller;

  /// i18n key.
  final String hint;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return MediaQuery.withNoTextScaling(
      child: Container(
        height: 50.ms,
        padding: EdgeInsets.symmetric(horizontal: 14.ms),
        decoration: BoxDecoration(
          color: p.tint,
          borderRadius: BorderRadius.circular(12.ms),
          border: Border.all(color: p.cardBorder),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.search, size: 18.ms, color: p.muted),
            SizedBox(width: 10.ms),
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                textInputAction: TextInputAction.search,
                cursorColor: p.accent,
                style: TextStyle(
                  color: p.text,
                  fontSize: 15.5.ms,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: context.t(hint),
                  hintStyle: TextStyle(color: p.faint),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
