import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../common/host_page.dart';
import '../../common/host_review.dart';
import '../helper/host_steps.dart';

/// What review asked to change on [step], at the top of the step: the text
/// fields a rejection named (with the team's own words), or a rejected
/// photo. Nothing when there is nothing to fix here.
class HostFixNotice extends StatelessWidget {
  const HostFixNotice({super.key, required this.step});
  final HostStep step;

  /// "display name and handle"; "tagline".
  static String fieldNames(BuildContext context, List<String> fields) {
    final names = [for (final f in fields) context.t('hostflow:fix.field.$f')];
    if (names.length < 2) return names.join();
    final and = context.t('hostflow:fix.and');
    return '${names.sublist(0, names.length - 1).join(', ')} $and ${names.last}';
  }

  @override
  Widget build(BuildContext context) {
    final review = HostReviewScope.of(context);
    final Widget? card;
    if (step == HostStep.photos && review.hasRejectedPhoto) {
      card = const HostToneCard(
        tone: HostTone.danger,
        icon: LucideIcons.imageOff,
        title: 'hostflow:fix.photos_title',
        message: 'hostflow:fix.photos_body',
      );
    } else if (review.noticeOn(step)) {
      final fields = review.fieldsOn(step);
      card = HostToneCard(
        tone: HostTone.danger,
        icon: LucideIcons.circleAlert,
        title: fields.isEmpty
            ? 'hostflow:moderation.rejected'
            : 'hostflow:fix.title',
        titleVariables: {'fields': fieldNames(context, fields)},
        message: review.note ?? context.t('hostflow:fix.body'),
        translateMessage: false,
      );
    } else {
      card = null;
    }
    if (card == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 14.ms),
      child: card,
    );
  }
}
