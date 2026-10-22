import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/utils/scale.dart';
import '../../api/resourcesscreen/resources_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../helper/resource_links.dart';
import '../helper/resource_palette.dart';

/// The rounded card the page content sits in (RN DynamicPageScreen).
class PageCard extends StatelessWidget {
  const PageCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    return Container(
      padding: EdgeInsets.all(16.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(24.ms),
        border: Border.all(color: p.border),
      ),
      child: child,
    );
  }
}

/// First load: a heading and paragraphs shaped like a page.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 6.ms),
        FractionallySizedBox(
          widthFactor: 0.6,
          child: SkeletonBox(height: 22.ms, radius: 8),
        ),
        SizedBox(height: 18.ms),
        for (final lines in const [4, 3, 5]) ...[
          SkeletonLines(lines: lines, height: 12.ms, gap: 9.ms),
          SizedBox(height: 18.ms),
        ],
      ],
    ),
  );
}

/// "No content available."
class PageEmpty extends StatelessWidget {
  const PageEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 40.ms),
      child: Column(
        children: [
          Icon(LucideIcons.fileText, size: 40.ms, color: p.muted),
          SizedBox(height: 10.ms),
          CText(
            'resources:page.empty',
            size: 14,
            weight: FontWeight.w700,
            color: p.muted,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Support contacts from app-config, when there is no `support` page.
class SupportContacts extends StatelessWidget {
  const SupportContacts({super.key, required this.contact});
  final SupportContact contact;

  @override
  Widget build(BuildContext context) {
    final p = ResourcePalette.of(context);
    Widget line(String label, String? value, String Function(String) link) {
      final v = value?.trim() ?? '';
      return Pressable(
        onPressed: v.isEmpty ? null : () => ResourceLinks.open(link(v)),
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 14, height: 22 / 14, color: p.text),
            children: [
              TextSpan(text: '${context.t(label)}: '),
              TextSpan(
                text: v.isEmpty ? '-' : v,
                style: v.isEmpty
                    ? null
                    : const TextStyle(
                        color: ResourcePalette.link,
                        decoration: TextDecoration.underline,
                        decorationColor: ResourcePalette.link,
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CText(
          'resources:support.fallback_intro',
          size: 15,
          weight: FontWeight.w800,
          color: p.text,
        ),
        SizedBox(height: 12.ms),
        line('resources:support.email', contact.email, ResourceLinks.mailto),
        line('resources:support.phone', contact.phone, ResourceLinks.tel),
        line(
          'resources:support.whatsapp',
          contact.whatsapp,
          ResourceLinks.whatsapp,
        ),
      ],
    );
  }
}
