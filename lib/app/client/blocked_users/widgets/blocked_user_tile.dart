import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../api/client/client_models.dart';
import '../../../component/c_image.dart';
import '../../../component/c_text.dart';
import '../../../component/pressable.dart';
import '../../../component/skeleton.dart';
import '../helper/blocked_palette.dart';

/// One blocked person (RN BlockedUsersScreen row): avatar, name, handle or
/// role, block date, Unblock.
class BlockedUserTile extends StatelessWidget {
  const BlockedUserTile({
    super.key,
    required this.user,
    required this.busy,
    required this.onUnblock,
  });

  final BlockedUser user;
  final bool busy;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final p = BlockedPalette.of(context);
    final accent = context.colors.accent;
    final name = user.name ?? context.t('client:fallback.blocked_user');
    final handle = user.handle;
    final subtitle = handle != null
        ? '@$handle'
        : (user.role ?? context.t('resources:blocked.user'));
    final at = user.blockedAt;
    return Container(
      margin: EdgeInsets.only(bottom: 10.ms),
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(20.ms),
        border: Border.all(color: p.cardBorder),
      ),
      child: Row(
        children: [
          CAvatar(url: user.profilePicUrl, name: name, size: 48.ms),
          SizedBox(width: 14.ms),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText.raw(
                  name,
                  size: 15,
                  weight: FontWeight.w800,
                  color: p.text,
                  maxLines: 1,
                ),
                SizedBox(height: 2.ms),
                CText.raw(
                  subtitle,
                  size: 12,
                  weight: FontWeight.w500,
                  color: p.muted,
                  maxLines: 1,
                ),
                if (at != null) ...[
                  SizedBox(height: 3.ms),
                  Opacity(
                    opacity: 0.7,
                    child: CText(
                      'resources:blocked.blocked_on',
                      variables: {
                        'date': DateFormat.yMd(
                          Localizations.localeOf(context).toLanguageTag(),
                        ).format(at.toLocal()),
                      },
                      size: 10,
                      weight: FontWeight.w500,
                      color: p.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 10.ms),
          Pressable(
            onPressed: busy ? null : onUnblock,
            activeOpacity: 0.8,
            child: Container(
              constraints: BoxConstraints(minWidth: 76.ms, minHeight: 32.ms),
              padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 7.ms),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: StatusColors.dangerRed.withValues(
                  alpha: p.isDark ? 0.1 : 0.06,
                ),
                borderRadius: BorderRadius.circular(14.ms),
                border: Border.all(color: accent, width: 1.5),
              ),
              child: busy
                  ? SizedBox.square(
                      dimension: 16.ms,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent,
                      ),
                    )
                  : CText(
                      'resources:blocked.unblock',
                      size: 12,
                      weight: FontWeight.w800,
                      color: accent,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First load: rows shaped like [BlockedUserTile].
class BlockedUsersSkeleton extends StatelessWidget {
  const BlockedUsersSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Column(
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 10.ms),
            child: SkeletonBox(height: 76.ms, radius: 20.ms),
          ),
      ],
    ),
  );
}

/// "No Blocked Users".
class BlockedUsersEmpty extends StatelessWidget {
  const BlockedUsersEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final p = BlockedPalette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.ms, vertical: 80.ms),
      child: Column(
        children: [
          Container(
            width: 76.ms,
            height: 76.ms,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.isDark ? AppColors.whiteA(0.05) : AppColors.blackA(0.03),
            ),
            child: Icon(
              LucideIcons.shieldCheck,
              size: 38.ms,
              color: context.colors.accent,
            ),
          ),
          SizedBox(height: 16.ms),
          CText(
            'resources:blocked.empty_title',
            size: 18,
            weight: FontWeight.w900,
            color: p.text,
            align: TextAlign.center,
          ),
          SizedBox(height: 8.ms),
          CText(
            'resources:blocked.empty_message',
            size: 13,
            weight: FontWeight.w500,
            color: p.muted,
            align: TextAlign.center,
            height: 18,
          ),
        ],
      ),
    );
  }
}
