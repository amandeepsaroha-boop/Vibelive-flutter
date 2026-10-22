import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_back_button.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../helper/resource_palette.dart';

/// DynamicPageScreen header: back, centered title, refresh.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.translate,
    required this.onRefresh,
    this.refreshing = false,
  });

  final String title;

  /// [title] is an i18n key (else server text).
  final bool translate;
  final VoidCallback onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    final titleText = translate
        ? CText(
            title,
            size: 18,
            weight: FontWeight.w900,
            color: p.text,
            maxLines: 1,
            align: TextAlign.center,
          )
        : CText.raw(
            title,
            size: 18,
            weight: FontWeight.w900,
            color: p.text,
            maxLines: 1,
            align: TextAlign.center,
          );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.ms, vertical: 14.ms),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          CBackButton(color: p.text),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.ms),
              child: Semantics(header: true, child: titleText),
            ),
          ),
          Pressable(
            onPressed: refreshing ? null : onRefresh,
            semanticLabel: context.t('resources:page.refresh'),
            child: AnimatedOpacity(
              opacity: refreshing ? 0.5 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 40.ms,
                height: 40.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.soft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: Icon(LucideIcons.refreshCcw, size: 16.ms, color: p.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
