import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_back_button.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../helper/personal_info_palette.dart';

/// Back, title, and the ✓ save button (RN header). Always on screen, so
/// Save stays reachable while the keyboard is up.
class PersonalInfoTopBar extends StatelessWidget {
  const PersonalInfoTopBar({
    super.key,
    required this.saving,
    required this.loading,
    required this.onBack,
    required this.onSave,
  });

  final ValueListenable<bool> saving;

  /// The profile is not loaded yet: nothing to save.
  final bool loading;
  final VoidCallback onBack;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final p = PersonalInfoPalette.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20.ms, 8.ms, 20.ms, 6.ms),
      child: Row(
        children: [
          CBackButton(onPressed: onBack, boxSize: 42, radius: 14, size: 20),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.ms),
              child: CText(
                'client:personal_info.title',
                size: 18,
                weight: FontWeight.w900,
                color: p.text,
                align: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: saving,
            builder: (_, busy, _) {
              final disabled = busy || loading;
              return Opacity(
                opacity: disabled ? 0.7 : 1,
                child: Pressable(
                  key: const ValueKey('personal_info.save'),
                  semanticLabel: context.t('client:personal_info.save'),
                  hitPadding: const EdgeInsets.all(4),
                  onPressed: disabled ? null : onSave,
                  child: Container(
                    constraints: BoxConstraints(minWidth: 42.ms),
                    height: 42.ms,
                    padding: EdgeInsets.symmetric(horizontal: 10.ms),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accentA(0.12),
                      borderRadius: BorderRadius.circular(14.ms),
                      border: Border.all(color: p.accentA(0.35)),
                    ),
                    child: busy
                        ? SizedBox.square(
                            dimension: 18.ms,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: p.accent,
                            ),
                          )
                        : Icon(LucideIcons.check, size: 18.ms, color: p.accent),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
