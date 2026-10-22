import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_queries.dart';
import '../../component/c_state_view.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/status_bar_style.dart';
import '../../component/vibe_background.dart';
import 'helper/blocked_actions.dart';
import 'helper/blocked_palette.dart';
import 'widgets/blocked_user_tile.dart';

/// `/me/blocked-users` (RN `BlockedUsersScreen`): who the user blocked,
/// with Unblock (confirm first). Pull to refresh.
class BlockedUsersScreen extends HookWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final blocked = useBlockedUsers(context);
    final unblock = useUnblockUser();
    final busyId = useState<String?>(null);
    // Gone right away (RN filtered them out), before the refetch lands.
    final removed = useState(const <String>{});
    final p = BlockedPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    Future<void> onUnblock(String id) async {
      final user = blocked.data?.where((u) => u.targetUserId == id).firstOrNull;
      if (user == null || busyId.value != null) return;
      busyId.value = id;
      final ok = await BlockedActions.confirmUnblock(
        context,
        user,
        unblock.mutateAsync,
      );
      if (!context.mounted) return;
      busyId.value = null;
      if (ok) removed.value = {...removed.value, id};
    }

    final data = blocked.data;
    final Widget body;
    if (data == null && blocked.isError && blocked.error != null) {
      body = CStateView.error(
        context,
        blocked.error!,
        onRetry: () => blocked.refetch(),
      );
    } else if (data == null) {
      body = Padding(
        padding: EdgeInsets.all(16.ms),
        child: const BlockedUsersSkeleton(),
      );
    } else {
      final list = [
        for (final u in data)
          if (!removed.value.contains(u.targetUserId)) u,
      ];
      body = RefreshIndicator(
        color: context.colors.accent,
        onRefresh: () async => blocked.refetch(),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16.ms, 16.ms, 16.ms, 16.ms + bottom),
          itemCount: list.isEmpty ? 1 : list.length,
          itemBuilder: (context, i) {
            if (list.isEmpty) return const BlockedUsersEmpty();
            final u = list[i];
            final id = u.targetUserId ?? '$i';
            return BlockedUserTile(
              key: ValueKey(id),
              user: u,
              busy: busyId.value == id,
              onUnblock: () => onUnblock(id),
            );
          },
        ),
      );
    }

    return ThemedStatusBar(
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: Stack(
          children: [
            const VibeBackground(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.ms,
                      vertical: 12.ms,
                    ),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: p.border)),
                    ),
                    child: Row(
                      children: [
                        Pressable(
                          onPressed: () => context.pop(),
                          semanticLabel: context.t('actions.back'),
                          child: Container(
                            width: 40.ms,
                            height: 40.ms,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.backBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.chevronLeft,
                              size: 24.ms,
                              color: p.text,
                            ),
                          ),
                        ),
                        Expanded(
                          child: CText(
                            'resources:blocked.title',
                            size: 17,
                            weight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: p.text,
                            align: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                        SizedBox(width: 40.ms),
                      ],
                    ),
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
