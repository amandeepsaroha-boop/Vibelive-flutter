import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/session/session_store.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/hosthub/profile_models.dart';
import '../../client/me/helper/host_availability_controller.dart';
import '../../client/me/helper/me_data.dart';
import '../../client/me/widgets/host_availability_sheet.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// Discover's promo banner, worded for who is looking:
/// - a client: why talk here, Start Talking (scrolls to the grid);
/// - a host: their status. Offline or on working hours: Go Online (one tap);
///   online: Manage Status (the availability sheet).
/// A bundled photo on the right: no network, never an empty box.
class DiscoverHero extends StatelessWidget {
  const DiscoverHero({super.key, required this.onExplore});

  final VoidCallback onExplore;

  static double get height => 160.ms;

  /// The photo's share of the card's width.
  static const _photoShare = 0.45;

  /// The photo, decoded at the width it is shown (cropped to cover the
  /// card's height: 1080 × 1620 is taller than the box).
  static ImageProvider photo(BuildContext context) =>
      ResizeImage.resizeIfNeeded(
        (MediaQuery.sizeOf(context).width *
                _photoShare *
                MediaQuery.devicePixelRatioOf(context))
            .round(),
        null,
        const AssetImage(AppImages.hostIntro),
      );

  /// Decodes [photo] ahead (the splash), so it never pops in.
  static Future<void> precache(BuildContext context) =>
      precacheImage(photo(context), context, onError: (_, _) {});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SessionState>(
    valueListenable: SessionStore.instance,
    builder: (_, session, _) {
      final me = MeData.of(session);
      if (!me.isExpert) {
        return _Banner(
          copy: 'home:hero.client',
          icon: LucideIcons.arrowRight,
          onAction: onExplore,
        );
      }
      // A mode being saved shows at once (Go Online flips the banner).
      return ValueListenableBuilder<HostAvailability?>(
        valueListenable: HostAvailabilityController.pending,
        builder: (_, pending, _) => switch (pending ?? me.availability) {
          HostAvailability.available => _Banner(
            copy: 'home:hero.host_online',
            icon: LucideIcons.slidersHorizontal,
            onAction: () => unawaited(
              showHostAvailabilitySheet(context, source: 'discover_banner'),
            ),
          ),
          final mode => _Banner(
            copy: mode == HostAvailability.custom
                ? 'home:hero.host_scheduled'
                : 'home:hero.host_offline',
            icon: LucideIcons.power,
            onAction: () {
              unawaited(HapticFeedback.selectionClick());
              unawaited(
                HostAvailabilityController.set(HostAvailability.available),
              );
            },
          ),
        },
      );
    },
  );
}

/// The card itself: gradient, photo on the right, title (second half in the
/// accent), a line and the button. [copy]: the i18n group with `title_a`,
/// `title_b`, `subtitle` and `action`.
class _Banner extends StatelessWidget {
  const _Banner({
    required this.copy,
    required this.icon,
    required this.onAction,
  });

  final String copy;
  final IconData icon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tints = c.isDark
        ? [
            Color.alphaBlend(c.accent.withValues(alpha: 0.30), c.bg),
            Color.alphaBlend(c.accent.withValues(alpha: 0.18), c.bg),
            Color.alphaBlend(c.accent.withValues(alpha: 0.32), c.bg),
          ]
        : const [Color(0xFFEDE9FE), Color(0xFFF3E8FF), Color(0xFFDDD6FE)];
    return Container(
      height: DiscoverHero.height,
      margin: EdgeInsets.fromLTRB(6.ms, 4.ms, 6.ms, 6.ms),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: tints),
        borderRadius: BorderRadius.circular(30.ms),
        border: Border.all(color: c.accent.withValues(alpha: 0.22)),
      ),
      child: LayoutBuilder(
        builder: (_, box) => Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: box.maxWidth * DiscoverHero._photoShare,
              child: Image(
                image: DiscoverHero.photo(context),
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.7), // her face
                gaplessPlayback: true,
                excludeFromSemantics: true,
              ),
            ),
            // The photo melts into the card behind the copy.
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: box.maxWidth * DiscoverHero._photoShare,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tints.first, tints.first.withValues(alpha: 0)],
                    stops: const [0, 0.5],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(18.ms),
              // Long copy (Hindi, a narrow phone) scales down, never clips.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: box.maxWidth * 0.6,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: context.t('$copy.title_a'),
                          children: [
                            TextSpan(
                              text: context.t('$copy.title_b'),
                              style: TextStyle(color: c.accent),
                            ),
                          ],
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 18.ms,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      SizedBox(height: 5.ms),
                      CText(
                        '$copy.subtitle',
                        size: 11,
                        weight: FontWeight.w600,
                        height: 15,
                        color: c.textMuted,
                        maxLines: 3,
                      ),
                      SizedBox(height: 10.ms),
                      // A long label (Hindi, 320 px) shrinks the button.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Pressable(
                          activeOpacity: 0.85,
                          onPressed: onAction,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14.ms,
                              vertical: 7.ms,
                            ),
                            decoration: BoxDecoration(
                              color: c.accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CText(
                                  '$copy.action',
                                  size: 11.5,
                                  weight: FontWeight.w800,
                                  color: c.onAccent,
                                ),
                                SizedBox(width: 5.ms),
                                Icon(icon, size: 13.ms, color: c.onAccent),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
