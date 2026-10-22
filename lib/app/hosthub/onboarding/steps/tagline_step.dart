import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../helper/draft_controller.dart';
import '../helper/suggestions.dart';
import '../helper/validation.dart';
import '../widgets/host_field.dart';
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
      HostField(
        controller: draft.tagline,
        hint: 'hostflow:tagline.hint',
        maxLength: HostValidation.taglineMax,
        minLines: 2,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        fieldKey: const ValueKey('hostflow-tagline'),
      ),
      SizedBox(height: 14.ms),
      HostPromptSuggestions(
        topics: draft.topics,
        page: draft.taglineSeed,
        target: draft.tagline,
        source: HostSuggestions.taglines,
      ),
    ],
  );
}
