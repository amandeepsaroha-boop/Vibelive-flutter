import 'package:flutter/material.dart';

import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/gender_answer.dart';
import '../helper/personal_info_palette.dart';

/// Female / Male / Other as plain chips in the screen's field style.
class GenderChips extends StatelessWidget {
  const GenderChips({super.key, required this.gender});
  final ValueNotifier<String?> gender;

  static const _labels = {
    'Female': 'client:personal_info.gender.female',
    'Male': 'client:personal_info.gender.male',
    'Others': 'client:personal_info.gender.other',
  };

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    final onAccent = context.colors.onAccent;
    return ValueListenableBuilder<String?>(
      valueListenable: gender,
      builder: (_, value, _) => Row(
        children: [
          for (final (i, g) in GenderAnswer.values.indexed) ...[
            if (i > 0) SizedBox(width: 10.ms),
            Expanded(
              child: Semantics(
                selected: value == g,
                child: Pressable(
                  key: ValueKey('personal_info.gender.$g'),
                  onPressed: () => gender.value = g,
                  child: Container(
                    height: 48.ms,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == g ? p.accent : p.card,
                      borderRadius: BorderRadius.circular(16.ms),
                      border: Border.all(
                        color: value == g ? p.accent : p.border,
                      ),
                    ),
                    child: CText(
                      _labels[g]!,
                      size: 14,
                      weight: FontWeight.w700,
                      color: value == g ? onAccent : p.text,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
