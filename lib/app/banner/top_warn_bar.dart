import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/analytics/events/discover_events.dart';
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
  const TopWarnBar({super.key, this.onTap, this.moderation = false});

  /// Defaults to pushing the warning's route.
  final void Function(ProfileWarning warning)? onTap;

  /// Also the host's review state (Discover, as in RN; ME shows it as
  /// cards instead).
  final bool moderation;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SessionState>(
      valueListenable: SessionStore.instance,
      builder: (context, session, _) {
        final warning = ProfileWarning.from(session, moderation: moderation);
        if (warning == null) return const SizedBox.shrink();
        return _Bar(warning: warning, onTap: onTap);
      },
    );
  }
}

class _Bar extends StatefulWidget {
  const _Bar({required this.warning, required this.onTap});

  final ProfileWarning warning;
  final void Function(ProfileWarning warning)? onTap;

  @override
  State<_Bar> createState() => _BarState();
}

/// Logs the warning once it shows (once per type a session).
class _BarState extends State<_Bar> {
  void _shown() => DiscoverEvents.topWarnShown(
    type: widget.warning.type.name,
    missing: widget.warning.missing.length,
  );

  @override
  void initState() {
    super.initState();
    _shown();
  }

  @override
  void didUpdateWidget(_Bar old) {
    super.didUpdateWidget(old);
    if (old.warning.type != widget.warning.type) _shown();
  }

  @override
  Widget build(BuildContext context) =>
      _BarView(warning: widget.warning, onTap: widget.onTap);
}

class _BarView extends StatelessWidget {
  const _BarView({required this.warning, required this.onTap});

  final ProfileWarning warning;
  final void Function(ProfileWarning warning)? onTap;

  // RN REJECTED_COLOR / PENDING_COLOR.
  static const _rejected = Color(0xFFE11D48);
  static const _pending = Color(0xFFD97706);

  /// RN: "title: the reviewer's note" for a rejection; "Profile changes
  /// awaiting review" (text) or the notice's title while pending; plus
  /// " (+N more)" when there are other notices.
  String _moderationText(BuildContext context) {
    final n = warning.notice!;
    final extra = warning.more > 0
        ? context.t('banner:warn.more', variables: {'count': warning.more})
        : '';
    final title = context.t(n.title, variables: n.vars);
    if (warning.type == ProfileWarningType.moderationRejected) {
      return '$title: ${n.note ?? context.t(n.body!)}$extra';
    }
    final text = n.title == 'hostflow:moderation.pending'
        ? context.t('banner:warn.moderation_text')
        : title;
    return '$text$extra';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isApproval = warning.type == ProfileWarningType.approval;
    final color = switch (warning.type) {
      ProfileWarningType.moderationRejected => _rejected,
      ProfileWarningType.moderationPending => _pending,
      ProfileWarningType.personal || ProfileWarningType.approval => c.accent,
      _ => AppColors.orange,
    };
    final fields = warning.missing.map(context.t).join(', ');

    return Pressable(
      activeOpacity: 0.9,
      onPressed: () {
        DiscoverEvents.topWarnTapped(
          type: warning.type.name,
          route: warning.route,
        );
        onTap != null
            ? onTap!(warning)
            : GoRouter.of(context).push(warning.route);
      },
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
                      switch (warning.type) {
                        _ when isApproval => LucideIcons.circleCheck,
                        ProfileWarningType.moderationRejected =>
                          LucideIcons.circleX,
                        ProfileWarningType.moderationPending =>
                          LucideIcons.clock,
                        _ => LucideIcons.triangleAlert,
                      },
                      size: 18.ms,
                      color: color,
                    ),
                  ),
                  Expanded(
                    child: CText.raw(
                      warning.isModeration
                          ? _moderationText(context)
                          : context.t(
                              'banner:warn.${warning.type.name}',
                              variables: {'fields': fields},
                            ),
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
