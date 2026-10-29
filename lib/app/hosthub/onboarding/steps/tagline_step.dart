import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../common/host_review.dart';
import '../helper/draft_controller.dart';
import '../helper/host_steps.dart';
import '../helper/suggestions.dart';
import '../helper/validation.dart';
import '../widgets/enhance_field.dart';
import '../widgets/fix_notice.dart';
import '../widgets/prompt_suggestions.dart';
import '../widgets/step_body.dart';

/// 5 of 11: a one-line tagline (max 60), with ideas from the topics.
class TaglineStep extends StatelessWidget {
  const TaglineStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) => HostStepBody(
    title: 'hostflow:tagline.title',
    subtitle: 'hostflow:tagline.subtitle',
    children: [
      const HostFixNotice(step: HostStep.tagline),
      HostEnhanceField(
        controller: draft.tagline,
        hint: 'hostflow:tagline.hint',
        kind: 'tagline',
        maxLength: HostValidation.taglineMax,
        minLines: 2,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        fieldKey: const ValueKey('hostflow-tagline'),
        flagged: HostReviewScope.of(context).flagged('tagline'),
      ),
      SizedBox(height: 14.ms),
      HostPromptSuggestions(
        topics: draft.topics,
        page: draft.taglineSeed,
        target: draft.tagline,
        source: HostSuggestions.taglines,
        field: 'tagline',
      ),
    ],
  );
}
