import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/authscreen/auth_queries.dart';
import '../../hosthub/onboarding/helper/intro_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/me_actions.dart';
import 'helper/me_data.dart';
import 'helper/me_palette.dart';

/// Runs once the sheet is gone, with the screen's context.
typedef _AfterClose = Future<void> Function(BuildContext context);

/// The ME tab's ⋮ menu (RN `MeMenuSheet`): Share Profile for hosts, Become
/// a Host for clients, Logout for everyone.
Future<void> showMeMenu(BuildContext context) async {
  final after = await showModalBottomSheet<_AfterClose>(
    context: context,
    useRootNavigator: true,
    backgroundColor: AppColors.transparent,
    barrierColor: AppColors.blackA(0.6),
    builder: (_) => const _MeMenu(),
  );
  if (after != null && context.mounted) await after(context);
}

class _MeMenu extends HookWidget {
  const _MeMenu();

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    // Read once: a logout must not re-render the sheet as a client's.
    final data = useMemoized(() => MeData.of(SessionStore.instance.value));
    final loggingOut = useState(false);
    final nav = Navigator.of(context);

    void close([_AfterClose? after]) => nav.pop(after);

    // Stays open with a spinner while the server session is revoked; the
    // auth guard then replaces everything with the login screen.
    Future<void> signOut() async {
      if (loggingOut.value) return;
      loggingOut.value = true;
      await logout();
      if (context.mounted && nav.canPop()) close();
    }

    // RN: the expert handler, else the user documentId.
    final link = data.previewLink;
    // The fill runs under the home indicator; the content stays above it.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.isDark ? AppColors.darkSurface : AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 32.ms),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.ms, 12.ms, 24.ms, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(top: 12.ms, bottom: 24),
                  decoration: BoxDecoration(
                    color: p.isDark
                        ? AppColors.whiteA(0.1)
                        : AppColors.blackA(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: CText(
                  'client:me.menu.title',
                  size: 18,
                  weight: FontWeight.w900,
                  letterSpacing: 1,
                  color: p.text,
                ),
              ),
              if (data.isExpert)
                _MenuItem(
                  icon: LucideIcons.share2,
                  iconColor: BrandColors.lime,
                  label: 'client:me.menu.share',
                  onTap: link == null
                      ? null
                      : () => close(
                          (ctx) => MeActions.share(
                            ctx.t(
                              'client:me.share.my_message',
                              variables: {'link': link},
                            ),
                          ),
                        ),
                )
              else
                _MenuItem(
                  icon: LucideIcons.userPlus,
                  iconColor: p.accent,
                  label: 'client:me.menu.become_host',
                  onTap: data.hasBasics
                      ? () => close((ctx) async {
                          await HostIntroImage.precache(ctx);
                          if (ctx.mounted) {
                            await MeActions.open(ctx, AppRoutes.hostOnboarding);
                          }
                        })
                      : null,
                ),
              _MenuItem(
                icon: LucideIcons.logOut,
                iconColor: AppColors.logoutRed,
                label: 'client:me.menu.logout',
                loading: loggingOut.value,
                onTap: signOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final Color iconColor;

  /// i18n key.
  final String label;

  /// Null: disabled (shown at half opacity).
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = MePalette.of(context);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Pressable(
        activeOpacity: 0.85,
        onPressed: loading ? null : onTap,
        child: Container(
          height: 54.ms,
          margin: EdgeInsets.only(bottom: 8.ms),
          padding: EdgeInsets.symmetric(horizontal: 14.ms),
          decoration: BoxDecoration(
            color: p.isDark ? AppColors.whiteA(0.04) : AppColors.blackA(0.02),
            borderRadius: BorderRadius.circular(16.ms),
            border: Border.all(
              color: p.isDark ? AppColors.whiteA(0.08) : AppColors.blackA(0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34.ms,
                height: 34.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.isDark
                      ? AppColors.whiteA(0.06)
                      : AppColors.blackA(0.04),
                  borderRadius: BorderRadius.circular(12.ms),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              SizedBox(width: 12.ms),
              Expanded(
                child: CText(
                  label,
                  size: 15,
                  weight: FontWeight.w700,
                  color: p.pillText,
                  maxLines: 1,
                ),
              ),
              if (loading)
                SizedBox.square(
                  dimension: 18.ms,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
