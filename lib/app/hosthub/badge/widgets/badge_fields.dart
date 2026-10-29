import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/hosthub/verification_models.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../onboarding/helper/host_palette.dart';
import '../../onboarding/widgets/host_chip.dart';
import '../../onboarding/widgets/option_list.dart';
import '../../onboarding/widgets/sheet_frame.dart';
import '../helper/badge_form.dart';

/// Document type picker (RN "Select document type").
Future<String?> showDocTypePicker(BuildContext context, String? selected) =>
    showHostSheet<String>(
      context,
      title: 'hostflow:badge.doc_type',
      name: 'badge_doc_type_sheet',
      child: HostOptionList<String>(
        items: BadgeFormController.idTypes,
        labelOf: (t) => context.t(BadgeFormController.idTypeKey(t)),
        isSelected: (t) => t == selected,
        onTap: (t) => Navigator.of(context).pop(t),
      ),
    );

/// One identity photo (front / back): tap to pick, retry when it failed.
class BadgeDocTile extends StatelessWidget {
  const BadgeDocTile({
    super.key,
    required this.label,
    required this.doc,
    required this.onTap,
  });

  /// i18n key.
  final String label;
  final ValueListenable<BadgeDoc?> doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return LayoutBuilder(
      builder: (_, box) => ValueListenableBuilder<BadgeDoc?>(
        valueListenable: doc,
        builder: (_, d, _) {
          final w = box.maxWidth;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final Widget preview = d?.url != null
              ? CImage(url: d!.url, width: w)
              : d?.localPath != null
              ? Image.file(
                  File(d!.localPath!),
                  width: w,
                  fit: BoxFit.cover,
                  cacheWidth: (w * dpr).round(),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.imagePlus, size: 26.ms, color: p.accent),
                    SizedBox(height: 6.ms),
                    CText(
                      label,
                      size: 13,
                      weight: FontWeight.w600,
                      color: p.muted,
                      align: TextAlign.center,
                    ),
                  ],
                );
          return Semantics(
            label: context.t(label),
            child: Pressable(
              onPressed: onTap,
              child: AspectRatio(
                aspectRatio: 1.45,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.tint,
                    borderRadius: BorderRadius.circular(14.ms),
                    border: Border.all(
                      color: d?.failed == true ? p.danger : p.tintBorder,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: preview),
                      if (d?.uploading == true)
                        Center(
                          child: SizedBox.square(
                            dimension: 22.ms,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: p.accent,
                            ),
                          ),
                        ),
                      if (d?.failed == true)
                        Center(
                          child: Icon(
                            LucideIcons.refreshCw,
                            size: 22.ms,
                            color: p.danger,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Instagram / Facebook / Snapchat choice of the social step.
class BadgePlatformChips extends StatelessWidget {
  const BadgePlatformChips({super.key, required this.platform});
  final ValueNotifier<SocialPlatform> platform;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SocialPlatform>(
    valueListenable: platform,
    builder: (_, value, _) => Row(
      children: [
        for (final (i, s) in SocialPlatform.values.indexed) ...[
          if (i > 0) SizedBox(width: 8.ms),
          Expanded(
            child: HostChip(
              label: 'hostflow:badge.social.${s.name}',
              selected: s == value,
              fontSize: 14,
              onTap: () => platform.value = s,
            ),
          ),
        ],
      ],
    ),
  );
}
