import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/analytics/screen_tracker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// "Before you connect" (RN moderation prompt). True = start the call;
/// Cancel, a tap outside and back all mean no.
Future<bool> showSafetyPrompt(
  BuildContext context, {
  required bool video,
}) async {
  final start =
      await showGeneralDialog<bool>(
        context: context,
        routeSettings: ScreenTracker.sheet('call_safety_prompt'),
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: 'safety',
        barrierColor: AppColors.blackA(0.55),
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        pageBuilder: (_, _, _) => _SafetyCard(video: video),
      ) ==
      true;
  DiscoverEvents.safetyPromptAnswered(
    callType: video ? 'video' : 'audio',
    accepted: start,
  );
  return start;
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.video});
  final bool video;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    void answer(bool start) => Navigator.of(context).pop(start);
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 28.ms),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: EdgeInsets.fromLTRB(22.ms, 26.ms, 22.ms, 18.ms),
              decoration: BoxDecoration(
                color: c.modalCard,
                borderRadius: BorderRadius.circular(28.ms),
                border: Border.all(color: c.modalBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54.ms,
                    height: 54.ms,
                    margin: EdgeInsets.only(bottom: 14.ms),
                    decoration: BoxDecoration(
                      color: c.accentA(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.shieldCheck,
                      size: 26.ms,
                      color: c.accent,
                    ),
                  ),
                  CText(
                    'host:call.safety_title',
                    size: 18,
                    weight: FontWeight.w900,
                    color: c.modalText,
                    align: TextAlign.center,
                  ),
                  SizedBox(height: 8.ms),
                  CText(
                    'host:call.safety_message',
                    size: 12.5,
                    height: 19,
                    weight: FontWeight.w600,
                    color: c.modalMuted,
                    align: TextAlign.center,
                  ),
                  SizedBox(height: 22.ms),
                  Row(
                    children: [
                      Expanded(
                        flex: 10,
                        child: Pressable(
                          onPressed: () => answer(false),
                          activeOpacity: 0.85,
                          child: Container(
                            height: 50.ms,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: dark
                                  ? AppColors.whiteA(0.07)
                                  : AppColors.blackA(0.05),
                              borderRadius: BorderRadius.circular(16.ms),
                            ),
                            child: CText(
                              'actions.cancel',
                              size: 13.5,
                              weight: FontWeight.w800,
                              color: dark
                                  ? AppColors.whiteA(0.75)
                                  : AppColors.blackA(0.6),
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10.ms),
                      Expanded(
                        flex: 13,
                        child: Pressable(
                          onPressed: () => answer(true),
                          activeOpacity: 0.85,
                          child: Container(
                            height: 50.ms,
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(16.ms),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Same glyph as the button that was tapped.
                                Icon(
                                  video ? Icons.videocam : Icons.call,
                                  size: 18.ms,
                                  color: c.onAccent,
                                ),
                                SizedBox(width: 8.ms),
                                Flexible(
                                  child: CText(
                                    'host:call.start',
                                    size: 13.5,
                                    weight: FontWeight.w900,
                                    color: c.onAccent,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
