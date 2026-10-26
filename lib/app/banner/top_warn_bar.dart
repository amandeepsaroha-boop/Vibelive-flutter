import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../component/c_text.dart';
import '../component/pressable.dart';
import 'helper/profile_warning.dart';

export 'helper/profile_warning.dart';

/// RN `TopWarnBar`: tappable profile-completion warning under the top bar.
/// Renders nothing when the profile is complete.
class TopWarnBar extends StatelessWidget {
  const TopWarnBar({super.key, this.onTap});

  /// Defaults to pushing the warning's route.
  final void Function(ProfileWarning warning)? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SessionState>(
      valueListenable: SessionStore.instance,
      builder: (context, session, _) {
        final warning = ProfileWarning.from(session);
        if (warning == null) return const SizedBox.shrink();
        return _Bar(warning: warning, onTap: onTap);
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.warning, required this.onTap});

  final ProfileWarning warning;
  final void Function(ProfileWarning warning)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isApproval = warning.type == ProfileWarningType.approval;
    final color = switch (warning.type) {
      ProfileWarningType.personal || ProfileWarningType.approval => c.accent,
      _ => AppColors.orange,
    };
    final fields = warning.missing.map(context.t).join(', ');

    return Pressable(
      activeOpacity: 0.9,
      onPressed: () => onTap != null
          ? onTap!(warning)
          : GoRouter.of(context).push(warning.route),
      child: Container(
        margin: EdgeInsets.fromLTRB(16.ms, 8.ms, 16.ms, 4.ms),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.warnBarBg,
          borderRadius: BorderRadius.circular(16.ms),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: AppColors.blackA(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: color),
            ),
            Padding(
              padding: EdgeInsets.all(12.ms),
              child: Row(
                children: [
                  Container(
                    width: 32.ms,
                    height: 32.ms,
                    margin: EdgeInsets.only(right: 10.ms),
                    decoration: BoxDecoration(
                      color: AppColors.whiteA(0.05),
                      borderRadius: BorderRadius.circular(10.ms),
                    ),
                    child: Icon(
                      isApproval
                          ? LucideIcons.circleCheck
                          : LucideIcons.triangleAlert,
                      size: 18.ms,
                      color: color,
                    ),
                  ),
                  Expanded(
                    child: CText(
                      'banner:warn.${warning.type.name}',
                      variables: {'fields': fields},
                      size: 12,
                      height: 16,
                      weight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: c.contrast,
                      maxLines: 2,
                    ),
                  ),
                  SizedBox(width: 8.ms),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16.ms,
                    color: c.contrast.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
