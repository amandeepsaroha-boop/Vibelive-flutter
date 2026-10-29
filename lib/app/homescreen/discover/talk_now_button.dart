import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../callscreen/helper/call_actions.dart';
import '../../callscreen/helper/call_controller.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

class TalkNowButton extends StatelessWidget {
  const TalkNowButton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.ms, vertical: 6.ms),
      child: Pressable(
        activeOpacity: 0.85,
        onPressed: () {
          if (CallController.instance.isOnCall) return;
          unawaited(HapticFeedback.mediumImpact());
          unawaited(CallActions.talkNow());
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18.ms, vertical: 12.ms),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.accent, c.accent.withValues(alpha: 0.85)],
            ),
            borderRadius: BorderRadius.circular(16.ms),
            boxShadow: [
              BoxShadow(
                color: c.accent.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.phone, size: 18.ms, color: c.onAccent),
              SizedBox(width: 8.ms),
              CText(
                'home:talk_now.action',
                size: 14,
                weight: FontWeight.w800,
                color: c.onAccent,
              ),
              SizedBox(width: 6.ms),
              CText(
                'home:talk_now.subtitle',
                size: 11,
                weight: FontWeight.w500,
                color: c.onAccent.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
