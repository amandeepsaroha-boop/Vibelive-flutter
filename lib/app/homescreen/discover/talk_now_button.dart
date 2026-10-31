import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/instant_call/instant_call_queries.dart';
import '../../callscreen/helper/call_actions.dart';
import '../../callscreen/helper/call_controller.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// "Talk Now": one tap, the server finds a free host. Shown only while the
/// server has Talk Now on for this user (`/instant-call/config`, which
/// answers per user: the admin gives it to company accounts or to all);
/// off or unset, a tap could only fail. A host never sees it unless the
/// account is a company account.
class TalkNowButton extends HookWidget {
  const TalkNowButton({super.key});

  @override
  Widget build(BuildContext context) {
    final session = useValueListenable(SessionStore.instance);
    final config = useInstantCallConfig(context).data;
    final host = session.isExpert && !session.isCompanyAccount;
    if (host || config == null || !config.enabled) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.ms, vertical: 6.ms),
      child: Pressable(
        activeOpacity: 0.85,
        onPressed: () {
          final onCall = CallController.instance.isOnCall;
          DiscoverEvents.talkNowTapped(blockedByCall: onCall);
          if (onCall) return;
          unawaited(HapticFeedback.mediumImpact());
          unawaited(
            CallActions.talkNow(
              video: config.placesVideo,
              maxRingSeconds: config.maxRingSeconds,
            ),
          );
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
              // Long copy (Hindi, large text) shortens, never overflows.
              Flexible(
                child: CText(
                  'home:talk_now.action',
                  size: 14,
                  weight: FontWeight.w800,
                  color: c.onAccent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 6.ms),
              Flexible(
                flex: 2,
                child: CText(
                  'home:talk_now.subtitle',
                  size: 11,
                  weight: FontWeight.w500,
                  color: c.onAccent.withValues(alpha: 0.8),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
