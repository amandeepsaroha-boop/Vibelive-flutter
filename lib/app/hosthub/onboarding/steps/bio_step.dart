import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../helper/draft_controller.dart';
import '../helper/suggestions.dart';
import '../helper/validation.dart';
import '../widgets/host_field.dart';
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
      HostField(
        controller: draft.bio,
        hint: 'hostflow:bio.hint',
        maxLength: HostValidation.bioMax,
        minLines: 5,
        maxLines: 8,
        fieldKey: const ValueKey('hostflow-bio'),
      ),
      SizedBox(height: 14.ms),
      HostPromptSuggestions(
        topics: draft.topics,
        page: draft.bioSeed,
        target: draft.bio,
        source: HostSuggestions.bios,
      ),
    ],
  );
}
