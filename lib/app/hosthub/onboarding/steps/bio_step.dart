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

/// 6 of 11: "A little more about you" (the profile description, max 500).
class BioStep extends StatelessWidget {
  const BioStep({super.key, required this.draft});
  final HostDraftController draft;

  @override
  Widget build(BuildContext context) => HostStepBody(
    title: 'hostflow:bio.title',
    subtitle: 'hostflow:bio.subtitle',
    children: [
      const HostFixNotice(step: HostStep.bio),
      HostEnhanceField(
        controller: draft.bio,
        hint: 'hostflow:bio.hint',
        kind: 'bio',
        maxLength: HostValidation.bioMax,
        minLines: 5,
        maxLines: 8,
        fieldKey: const ValueKey('hostflow-bio'),
        flagged: HostReviewScope.of(context).flagged('descriptions'),
      ),
      SizedBox(height: 14.ms),
      HostPromptSuggestions(
        topics: draft.topics,
        page: draft.bioSeed,
        target: draft.bio,
        source: HostSuggestions.bios,
        field: 'bio',
      ),
    ],
  );
}
